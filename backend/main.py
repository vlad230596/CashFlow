import base64
import hashlib
import hmac
import json
import os
import re
import secrets
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from urllib.parse import urlparse
from urllib.request import Request, urlopen

import click
from flask import Flask, Response, g, jsonify, request, url_for
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import or_, select, text
from werkzeug.middleware.proxy_fix import ProxyFix

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get(
    'CASHFLOW_DATABASE_URL',
    'sqlite:///cards.db',
)
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['CASHFLOW_ENVIRONMENT'] = os.environ.get('CASHFLOW_ENVIRONMENT', 'development')
app.config['CASHFLOW_SESSION_TTL_HOURS'] = min(
    max(int(os.environ.get('CASHFLOW_SESSION_TTL_HOURS', '8760')), 1),
    8760,
)
trusted_hosts = [
    host.strip()
    for host in os.environ.get('CASHFLOW_TRUSTED_HOSTS', '').split(',')
    if host.strip()
]
if app.config['CASHFLOW_ENVIRONMENT'] == 'production' and not trusted_hosts:
    raise RuntimeError('CASHFLOW_TRUSTED_HOSTS is required in production')
if trusted_hosts:
    app.config['TRUSTED_HOSTS'] = trusted_hosts

db = SQLAlchemy(app)

allowed_origins = [
    origin.strip()
    for origin in os.environ.get('CASHFLOW_CORS_ORIGINS', '').split(',')
    if origin.strip()
]
CORS(
    app,
    origins=allowed_origins or [],
    allow_headers=['Authorization', 'Content-Type'],
    expose_headers=['X-CashFlow-Session-Expires-At'],
)
if app.config['CASHFLOW_ENVIRONMENT'] == 'production':
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1)

# Модель для банка
class Bank(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(50), unique=True, nullable=False)
    description = db.Column(db.Text)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description
        }


# Модель для владельца карты (только имя)
class CardUser(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name
        }


# Модель для банковской карты
class BankCard(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    payment_system = db.Column(db.String(20), nullable=False)  # Visa/MasterCard/Мир
    card_type = db.Column(db.String(10), nullable=False)  # physical/virtual
    last_four_digits = db.Column(db.String(4), nullable=False)

    bank_id = db.Column(db.Integer, db.ForeignKey('bank.id'), nullable=False)

    user_id = db.Column(db.Integer, db.ForeignKey('card_user.id'), nullable=False)

    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    is_active = db.Column(db.Boolean, default=True)
    max_cashback_categories = db.Column(db.Integer, default=4)

    def to_dict(self):
        return {
            'id': self.id,
            'payment_system': self.payment_system,
            'card_type': self.card_type,
            'last_four_digits': self.last_four_digits,
            'bank_id': self.bank_id,
            'user_id': self.user_id,
            'created_at': self.created_at.isoformat(),
            'is_active': self.is_active,
            'max_cashback_categories': self.max_cashback_categories
        }


# Модель для категорий кешбека
class CashbackCategory(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(50), nullable=False)
    start_date = db.Column(db.DateTime, nullable=False)
    end_date = db.Column(db.DateTime, nullable=False)
    is_selected = db.Column(db.Boolean, default=False)
    cashback_percent = db.Column(db.Float, nullable=False)
    description = db.Column(db.Text)
    category_type = db.Column(db.String(32), nullable=False, default='standard')
    is_selection_locked = db.Column(db.Boolean, nullable=False, default=False)
    is_bank_confirmed = db.Column(db.Boolean, nullable=False, default=False)
    max_cashback_amount = db.Column(db.Float)
    min_purchase_amount = db.Column(db.Float)

    card_id = db.Column(db.Integer, db.ForeignKey('bank_card.id'), nullable=False)
    card = db.relationship('BankCard', backref=db.backref('cashback_categories', lazy=True))

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'start_date': self.start_date.isoformat(),
            'end_date': self.end_date.isoformat(),
            'is_selected': self.is_selected,
            'cashback_percent': self.cashback_percent,
            'description': self.description,
            'category_type': self.category_type,
            'is_selection_locked': self.is_selection_locked,
            'is_bank_confirmed': self.is_bank_confirmed,
            'max_cashback_amount': self.max_cashback_amount,
            'min_purchase_amount': self.min_purchase_amount,
            'card_id': self.card_id
        }


class MccCode(db.Model):
    __tablename__ = 'mcc_code'
    __table_args__ = (db.CheckConstraint('length(code) = 4', name='ck_mcc_code_length'),)

    code = db.Column(db.String(4), primary_key=True)
    title = db.Column(db.String(255))
    description = db.Column(db.Text)
    reference_source = db.Column(db.Text)

    def to_dict(self):
        return {
            'code': self.code,
            'title': self.title,
            'description': self.description,
            'reference_source': self.reference_source,
        }


class BankCashbackProgram(db.Model):
    __tablename__ = 'bank_cashback_program'
    __table_args__ = (
        db.UniqueConstraint('bank_id', 'source_key', name='uq_program_bank_source_key'),
    )

    id = db.Column(db.Integer, primary_key=True)
    bank_id = db.Column(db.Integer, db.ForeignKey('bank.id'), nullable=False)
    source_key = db.Column(db.String(128), nullable=False)
    name = db.Column(db.String(255), nullable=False)
    product_scope = db.Column(db.String(255))


class RuleSourceSnapshot(db.Model):
    __tablename__ = 'rule_source_snapshot'

    id = db.Column(db.Integer, primary_key=True)
    source_type = db.Column(db.String(32), nullable=False)
    source_url = db.Column(db.Text)
    fetched_at = db.Column(db.DateTime(timezone=True), nullable=False)
    published_at = db.Column(db.DateTime(timezone=True))
    content_hash = db.Column(db.String(64), unique=True, nullable=False)
    raw_content = db.Column(db.Text, nullable=False)
    parser_name = db.Column(db.String(128))
    parser_version = db.Column(db.String(64))


class BankRuleRevision(db.Model):
    __tablename__ = 'bank_rule_revision'
    __table_args__ = (
        db.UniqueConstraint(
            'program_id',
            'normalized_hash',
            name='uq_revision_program_hash',
        ),
        db.Index('ix_bank_rule_revision_period', 'program_id', 'valid_from', 'valid_to'),
    )

    id = db.Column(db.Integer, primary_key=True)
    program_id = db.Column(
        db.Integer,
        db.ForeignKey('bank_cashback_program.id'),
        nullable=False,
    )
    valid_from = db.Column(db.DateTime(timezone=True), nullable=False)
    valid_to = db.Column(db.DateTime(timezone=True))
    validity_confidence = db.Column(db.String(16), nullable=False)
    recorded_at = db.Column(db.DateTime(timezone=True), nullable=False)
    last_seen_at = db.Column(db.DateTime(timezone=True), nullable=False)
    published_recorded_at = db.Column(db.DateTime(timezone=True))
    superseded_at = db.Column(db.DateTime(timezone=True))
    source_snapshot_id = db.Column(
        db.Integer,
        db.ForeignKey('rule_source_snapshot.id'),
        nullable=False,
    )
    completeness = db.Column(db.String(16), nullable=False)
    status = db.Column(db.String(16), nullable=False)
    normalized_hash = db.Column(db.String(64), nullable=False)


class BankCategory(db.Model):
    __tablename__ = 'bank_category'
    __table_args__ = (
        db.UniqueConstraint(
            'program_id',
            'source_key',
            name='uq_category_program_source_key',
        ),
    )

    id = db.Column(db.Integer, primary_key=True)
    program_id = db.Column(
        db.Integer,
        db.ForeignKey('bank_cashback_program.id'),
        nullable=False,
    )
    source_external_id = db.Column(db.String(255))
    source_key = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), nullable=False)


class BankCategoryRevision(db.Model):
    __tablename__ = 'bank_category_revision'
    __table_args__ = (
        db.UniqueConstraint(
            'rule_revision_id',
            'bank_category_id',
            name='uq_category_revision_rule_category',
        ),
    )

    id = db.Column(db.Integer, primary_key=True)
    rule_revision_id = db.Column(
        db.Integer,
        db.ForeignKey('bank_rule_revision.id'),
        nullable=False,
    )
    bank_category_id = db.Column(
        db.Integer,
        db.ForeignKey('bank_category.id'),
        nullable=False,
    )
    original_name = db.Column(db.String(255), nullable=False)
    original_description = db.Column(db.Text)
    source_payload = db.Column(db.JSON)


class BankCategoryMccRule(db.Model):
    __tablename__ = 'bank_category_mcc_rule'
    __table_args__ = (
        db.CheckConstraint("effect IN ('include', 'exclude')", name='ck_category_mcc_effect'),
        db.Index('ix_bank_category_mcc_rule_mcc', 'mcc_code'),
    )

    category_revision_id = db.Column(
        db.Integer,
        db.ForeignKey('bank_category_revision.id'),
        primary_key=True,
    )
    mcc_code = db.Column(
        db.String(4),
        db.ForeignKey('mcc_code.code'),
        primary_key=True,
    )
    effect = db.Column(db.String(16), primary_key=True)


class BankProgramExclusion(db.Model):
    __tablename__ = 'bank_program_exclusion'
    __table_args__ = (db.Index('ix_bank_program_exclusion_mcc', 'mcc_code'),)

    rule_revision_id = db.Column(
        db.Integer,
        db.ForeignKey('bank_rule_revision.id'),
        primary_key=True,
    )
    mcc_code = db.Column(
        db.String(4),
        db.ForeignKey('mcc_code.code'),
        primary_key=True,
    )
    reason = db.Column(db.Text)


class BankRuleCondition(db.Model):
    __tablename__ = 'bank_rule_condition'

    id = db.Column(db.Integer, primary_key=True)
    rule_revision_id = db.Column(
        db.Integer,
        db.ForeignKey('bank_rule_revision.id'),
        nullable=False,
    )
    category_revision_id = db.Column(
        db.Integer,
        db.ForeignKey('bank_category_revision.id'),
    )
    kind = db.Column(db.String(32), nullable=False)
    operator = db.Column(db.String(32))
    value = db.Column(db.Text)
    original_text = db.Column(db.Text, nullable=False)


class AuthUser(db.Model):
    __tablename__ = 'auth_user'

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), unique=True, nullable=False)
    password_hash = db.Column(db.Text, nullable=False)
    role = db.Column(db.String(16), nullable=False, default='viewer')
    auth_enabled = db.Column(db.Boolean, nullable=False, default=True)
    created_at = db.Column(db.DateTime(timezone=True), nullable=False)
    updated_at = db.Column(db.DateTime(timezone=True), nullable=False)

    def to_dict(self):
        return {
            'id': self.id,
            'username': self.username,
            'role': self.role,
            'auth_enabled': self.auth_enabled,
        }


class AuthSession(db.Model):
    __tablename__ = 'auth_session'

    id = db.Column(db.Integer, primary_key=True)
    token_digest = db.Column(db.String(64), unique=True, nullable=False)
    user_id = db.Column(
        db.Integer,
        db.ForeignKey('auth_user.id', ondelete='CASCADE'),
        nullable=False,
    )
    created_at = db.Column(db.DateTime(timezone=True), nullable=False)
    expires_at = db.Column(db.DateTime(timezone=True), nullable=False)


class AuthLoginAttempt(db.Model):
    __tablename__ = 'auth_login_attempt'

    id = db.Column(db.Integer, primary_key=True)
    key_digest = db.Column(db.String(64), unique=True, nullable=False)
    failed_count = db.Column(db.Integer, nullable=False, default=0)
    window_started_at = db.Column(db.DateTime(timezone=True), nullable=False)
    blocked_until = db.Column(db.DateTime(timezone=True))


class PartnerMerchant(db.Model):
    __tablename__ = 'partner_merchant'

    id = db.Column(db.Integer, primary_key=True)
    canonical_key = db.Column(db.String(255), unique=True, nullable=False)
    display_name = db.Column(db.String(255), nullable=False)
    domain = db.Column(db.String(255))
    created_at = db.Column(db.DateTime(timezone=True), nullable=False)


class PartnerMerchantAlias(db.Model):
    __tablename__ = 'partner_merchant_alias'
    __table_args__ = (
        db.UniqueConstraint(
            'bank_id',
            'source_key',
            name='uq_partner_merchant_alias_bank_source',
        ),
    )

    id = db.Column(db.Integer, primary_key=True)
    merchant_id = db.Column(
        db.Integer,
        db.ForeignKey('partner_merchant.id', ondelete='CASCADE'),
        nullable=False,
    )
    bank_id = db.Column(db.Integer, db.ForeignKey('bank.id'), nullable=False)
    source_key = db.Column(db.String(255), nullable=False)
    source_name = db.Column(db.String(255))


class PartnerOffer(db.Model):
    __tablename__ = 'partner_offer'
    __table_args__ = (
        db.UniqueConstraint(
            'bank_id',
            'card_user_id',
            'source_key',
            name='uq_partner_offer_profile_source',
        ),
        db.Index('ix_partner_offer_profile_available', 'card_user_id', 'is_available'),
        db.Index('ix_partner_offer_bank_available', 'bank_id', 'is_available'),
    )

    id = db.Column(db.Integer, primary_key=True)
    bank_id = db.Column(db.Integer, db.ForeignKey('bank.id'), nullable=False)
    card_user_id = db.Column(db.Integer, db.ForeignKey('card_user.id'), nullable=False)
    merchant_id = db.Column(db.Integer, db.ForeignKey('partner_merchant.id'))
    source_key = db.Column(db.String(255), nullable=False)
    source_external_id = db.Column(db.String(255))
    # Kept as an application-managed reference so the same migration works on
    # PostgreSQL and SQLite despite the offer/snapshot creation cycle.
    current_snapshot_id = db.Column(db.Integer)
    first_seen_at = db.Column(db.DateTime(timezone=True), nullable=False)
    last_seen_at = db.Column(db.DateTime(timezone=True), nullable=False)
    is_available = db.Column(db.Boolean, nullable=False, default=True)
    unavailable_at = db.Column(db.DateTime(timezone=True))


class PartnerOfferSnapshot(db.Model):
    __tablename__ = 'partner_offer_snapshot'
    __table_args__ = (
        db.UniqueConstraint(
            'offer_id',
            'content_hash',
            name='uq_partner_offer_snapshot_content',
        ),
        db.CheckConstraint(
            "benefit_kind IN ('cashback', 'discount', 'other')",
            name='ck_partner_offer_snapshot_benefit_kind',
        ),
        db.CheckConstraint(
            "rate_qualifier IN ('exact', 'up_to', 'from', 'unknown')",
            name='ck_partner_offer_snapshot_rate_qualifier',
        ),
        db.CheckConstraint(
            "details_status IN ('complete', 'preview_only', 'error')",
            name='ck_partner_offer_snapshot_details_status',
        ),
        db.Index('ix_partner_offer_snapshot_ends_at', 'ends_at'),
    )

    id = db.Column(db.Integer, primary_key=True)
    offer_id = db.Column(
        db.Integer,
        db.ForeignKey('partner_offer.id', ondelete='CASCADE'),
        nullable=False,
    )
    collected_at = db.Column(db.DateTime(timezone=True), nullable=False)
    details_collected_at = db.Column(db.DateTime(timezone=True))
    title = db.Column(db.String(500), nullable=False)
    description = db.Column(db.Text)
    benefit_kind = db.Column(db.String(16), nullable=False)
    rate_value = db.Column(db.Numeric(12, 4))
    rate_qualifier = db.Column(db.String(16), nullable=False)
    rate_label = db.Column(db.String(255))
    starts_at = db.Column(db.DateTime(timezone=True))
    ends_at = db.Column(db.DateTime(timezone=True))
    validity_label = db.Column(db.String(255))
    validity_precision = db.Column(db.String(16), nullable=False, default='unknown')
    preview_text = db.Column(db.Text)
    conditions = db.Column(db.Text)
    steps_json = db.Column(db.Text, nullable=False, default='[]')
    links_json = db.Column(db.Text, nullable=False, default='[]')
    requirements_json = db.Column(db.Text, nullable=False, default='[]')
    details_status = db.Column(db.String(16), nullable=False)
    details_error = db.Column(db.Text)
    source_url = db.Column(db.Text)
    icon_url = db.Column(db.Text)
    artwork_url = db.Column(db.Text)
    raw_json = db.Column(db.Text, nullable=False)
    content_hash = db.Column(db.String(64), nullable=False)


class PartnerOfferLimit(db.Model):
    __tablename__ = 'partner_offer_limit'
    __table_args__ = (
        db.CheckConstraint(
            "unit IN ('RUB', 'bonus', 'points', 'unknown')",
            name='ck_partner_offer_limit_unit',
        ),
        db.CheckConstraint(
            "scope IN ('purchase', 'month', 'campaign', 'unknown')",
            name='ck_partner_offer_limit_scope',
        ),
    )

    id = db.Column(db.Integer, primary_key=True)
    snapshot_id = db.Column(
        db.Integer,
        db.ForeignKey('partner_offer_snapshot.id', ondelete='CASCADE'),
        nullable=False,
    )
    limit_type = db.Column(db.String(32), nullable=False)
    value = db.Column(db.Numeric(14, 4))
    unit = db.Column(db.String(16), nullable=False)
    scope = db.Column(db.String(16), nullable=False)
    original_text = db.Column(db.Text, nullable=False)


class PartnerOfferPreference(db.Model):
    __tablename__ = 'partner_offer_preference'
    __table_args__ = (
        db.UniqueConstraint(
            'auth_user_id',
            'offer_id',
            name='uq_partner_offer_preference_user_offer',
        ),
        db.CheckConstraint(
            "rating IN ('interesting', 'undecided', 'hidden')",
            name='ck_partner_offer_preference_rating',
        ),
        db.Index('ix_partner_offer_preference_user_rating', 'auth_user_id', 'rating'),
    )

    id = db.Column(db.Integer, primary_key=True)
    auth_user_id = db.Column(
        db.Integer,
        db.ForeignKey('auth_user.id', ondelete='CASCADE'),
        nullable=False,
    )
    offer_id = db.Column(
        db.Integer,
        db.ForeignKey('partner_offer.id', ondelete='CASCADE'),
        nullable=False,
    )
    rating = db.Column(db.String(16), nullable=False, default='undecided')
    created_at = db.Column(db.DateTime(timezone=True), nullable=False)
    updated_at = db.Column(db.DateTime(timezone=True), nullable=False)


class PartnerOfferHideRule(db.Model):
    __tablename__ = 'partner_offer_hide_rule'
    __table_args__ = (
        db.CheckConstraint(
            "scope IN ('offer', 'campaign', 'merchant_bank', 'merchant_all_banks')",
            name='ck_partner_offer_hide_rule_scope',
        ),
        db.Index('ix_partner_offer_hide_rule_user_active', 'auth_user_id', 'revoked_at'),
    )

    id = db.Column(db.Integer, primary_key=True)
    auth_user_id = db.Column(
        db.Integer,
        db.ForeignKey('auth_user.id', ondelete='CASCADE'),
        nullable=False,
    )
    scope = db.Column(db.String(32), nullable=False)
    offer_id = db.Column(db.Integer, db.ForeignKey('partner_offer.id', ondelete='CASCADE'))
    merchant_id = db.Column(db.Integer, db.ForeignKey('partner_merchant.id'))
    bank_id = db.Column(db.Integer, db.ForeignKey('bank.id'))
    campaign_key = db.Column(db.String(255))
    created_at = db.Column(db.DateTime(timezone=True), nullable=False)
    revoked_at = db.Column(db.DateTime(timezone=True))


class PartnerOfferAsset(db.Model):
    __tablename__ = 'partner_offer_asset'

    id = db.Column(db.Integer, primary_key=True)
    content_hash = db.Column(db.String(64), unique=True, nullable=False)
    mime_type = db.Column(db.String(127), nullable=False)
    storage_path = db.Column(db.Text, nullable=False)
    source_url = db.Column(db.Text)
    status = db.Column(db.String(32), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), nullable=False)


class PartnerOfferImportRun(db.Model):
    __tablename__ = 'partner_offer_import_run'
    __table_args__ = (
        db.CheckConstraint(
            "completeness IN ('complete', 'partial', 'unknown')",
            name='ck_partner_offer_import_run_completeness',
        ),
        db.Index(
            'ix_partner_offer_import_run_profile_collected',
            'card_user_id',
            'collected_at',
        ),
    )

    id = db.Column(db.Integer, primary_key=True)
    bank_id = db.Column(db.Integer, db.ForeignKey('bank.id'), nullable=False)
    card_user_id = db.Column(db.Integer, db.ForeignKey('card_user.id'), nullable=False)
    imported_by_id = db.Column(db.Integer, db.ForeignKey('auth_user.id'), nullable=False)
    collected_at = db.Column(db.DateTime(timezone=True), nullable=False)
    imported_at = db.Column(db.DateTime(timezone=True), nullable=False)
    preview_count = db.Column(db.Integer, nullable=False, default=0)
    details_count = db.Column(db.Integer, nullable=False, default=0)
    completeness = db.Column(db.String(16), nullable=False)
    errors_json = db.Column(db.Text, nullable=False, default='[]')
    collector_version = db.Column(db.String(64))
    source_hash = db.Column(db.String(64), nullable=False)


ROLE_LEVELS = {'viewer': 10, 'editor': 20, 'admin': 30}
PUBLIC_ENDPOINTS = {'health', 'ready', 'version', 'login', 'partner_offer_icon'}
AUTH_TOKEN_BYTES = 32
LOGIN_WINDOW = timedelta(minutes=15)
LOGIN_MAX_FAILURES = 5
PARTNER_ICON_HOSTS = {
    'alfaonline.servicecdn.ru',
    'avatars.mds.yandex.net',
    'cdn1.ozone.ru',
    'cdnweb.sberbank.ru',
    'fintech-frontend.s3.yandex.net',
    'h2.sbpvtb.ru',
    'imgproxy.cdn-tinkoff.ru',
    'storage-vtb.seller-hub.ru',
}
PARTNER_ICON_MAX_BYTES = 5 * 1024 * 1024
USERNAME_PATTERN = re.compile(r'^[a-z0-9][a-z0-9._-]{2,63}$')


def _utc_now():
    return datetime.now(timezone.utc)


def _as_utc(value):
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _normalize_username(value):
    username = str(value or '').strip().lower()
    if not USERNAME_PATTERN.fullmatch(username):
        raise ValueError(
            'Username must be 3-64 characters: a-z, 0-9, dot, dash or underscore'
        )
    return username


def _hash_password(password):
    if len(password) < 12:
        raise ValueError('Password must contain at least 12 characters')
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(
        password.encode('utf-8'),
        salt=salt,
        n=16384,
        r=8,
        p=1,
        dklen=32,
        maxmem=64 * 1024 * 1024,
    )
    return 'scrypt$16384$8$1${}${}'.format(
        base64.urlsafe_b64encode(salt).decode('ascii'),
        base64.urlsafe_b64encode(digest).decode('ascii'),
    )


def _verify_password(password, encoded):
    try:
        algorithm, n, r, p, salt_text, digest_text = encoded.split('$')
        if algorithm != 'scrypt':
            return False
        expected = base64.urlsafe_b64decode(digest_text.encode('ascii'))
        actual = hashlib.scrypt(
            password.encode('utf-8'),
            salt=base64.urlsafe_b64decode(salt_text.encode('ascii')),
            n=int(n),
            r=int(r),
            p=int(p),
            dklen=len(expected),
            maxmem=64 * 1024 * 1024,
        )
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def _token_digest(token):
    return hashlib.sha256(token.encode('utf-8')).hexdigest()


def _login_attempt_key(username):
    remote_address = request.remote_addr or 'unknown'
    return hashlib.sha256(f'{username}\0{remote_address}'.encode('utf-8')).hexdigest()


def _required_role():
    if request.path.startswith(('/api/auth/users', '/api/admin/')):
        return 'admin'
    if request.path in ('/api/auth/me', '/api/auth/logout'):
        return 'viewer'
    if request.path.startswith('/api/partner-offers/') and (
        request.path.endswith('/preference')
        or request.path.startswith('/api/partner-offers/hide-rules')
    ):
        return 'viewer'
    if request.method in ('GET', 'HEAD'):
        return 'viewer'
    if request.path.startswith(('/api/banks', '/api/users', '/api/cards')):
        return 'admin'
    return 'editor'


@app.before_request
def authenticate_request():
    if request.method == 'OPTIONS' or request.endpoint in PUBLIC_ENDPOINTS:
        return None

    header = request.headers.get('Authorization', '')
    scheme, separator, token = header.partition(' ')
    if not separator or scheme.lower() != 'bearer' or not token:
        return jsonify({'error': 'Authentication required'}), 401

    session = AuthSession.query.filter_by(token_digest=_token_digest(token)).first()
    now = _utc_now()
    if session is None or _as_utc(session.expires_at) <= now:
        if session is not None:
            db.session.delete(session)
            db.session.commit()
        return jsonify({'error': 'Session expired'}), 401

    user = db.session.get(AuthUser, session.user_id)
    if user is None or not user.auth_enabled or user.role not in ROLE_LEVELS:
        return jsonify({'error': 'Authentication required'}), 401

    required_role = _required_role()
    if ROLE_LEVELS[user.role] < ROLE_LEVELS[required_role]:
        return jsonify({'error': 'Insufficient permissions'}), 403

    g.auth_user = user
    g.auth_session = session

    # Sliding expiration keeps regularly used installations signed in without
    # keeping abandoned sessions alive forever. Refresh at most twice per TTL.
    session_ttl = timedelta(hours=app.config['CASHFLOW_SESSION_TTL_HOURS'])
    if _as_utc(session.expires_at) - now < session_ttl / 2:
        session.expires_at = now + session_ttl
        db.session.commit()
    return None


@app.after_request
def expose_session_expiration(response):
    session = getattr(g, 'auth_session', None)
    if session is not None:
        response.headers['X-CashFlow-Session-Expires-At'] = (
            _as_utc(session.expires_at).isoformat()
        )
    return response


@app.get('/health')
def health():
    return jsonify({'status': 'healthy'})


@app.get('/ready')
def ready():
    db.session.execute(text('SELECT 1'))
    return jsonify({'status': 'ready'})


@app.get('/version')
def version():
    return jsonify({
        'version': os.environ.get('APP_VERSION', 'dev'),
        'build_date': os.environ.get('BUILD_DATE', 'unknown'),
    })


@app.post('/api/auth/login')
def login():
    if not request.is_json:
        return jsonify({'error': 'JSON request required'}), 415
    payload = request.get_json(silent=True) or {}
    try:
        username = _normalize_username(payload.get('username'))
    except ValueError:
        username = str(payload.get('username') or '').strip().lower()[:64]
    password = payload.get('password')
    if not isinstance(password, str):
        password = ''

    attempt_key = _login_attempt_key(username)
    attempt = AuthLoginAttempt.query.filter_by(key_digest=attempt_key).first()
    now = _utc_now()
    if attempt is not None and attempt.blocked_until is not None:
        if _as_utc(attempt.blocked_until) > now:
            return jsonify({'error': 'Too many login attempts. Try again later'}), 429
        db.session.delete(attempt)
        db.session.flush()
        attempt = None

    user = AuthUser.query.filter_by(username=username).first()
    password_matches = False
    if user is not None:
        password_matches = _verify_password(password, user.password_hash)
    else:
        hashlib.scrypt(
            password.encode('utf-8'),
            salt=b'cashflow-invalid',
            n=16384,
            r=8,
            p=1,
            dklen=32,
            maxmem=64 * 1024 * 1024,
        )

    if user is None or not password_matches or not user.auth_enabled:
        if attempt is None:
            attempt = AuthLoginAttempt(
                key_digest=attempt_key,
                failed_count=0,
                window_started_at=now,
            )
            db.session.add(attempt)
        elif now - _as_utc(attempt.window_started_at) >= LOGIN_WINDOW:
            attempt.failed_count = 0
            attempt.window_started_at = now
        attempt.failed_count += 1
        if attempt.failed_count >= LOGIN_MAX_FAILURES:
            attempt.blocked_until = now + LOGIN_WINDOW
        db.session.commit()
        return jsonify({'error': 'Invalid username or password'}), 401

    if attempt is not None:
        db.session.delete(attempt)
    token = secrets.token_urlsafe(AUTH_TOKEN_BYTES)
    expires_at = now + timedelta(hours=app.config['CASHFLOW_SESSION_TTL_HOURS'])
    session = AuthSession(
        token_digest=_token_digest(token),
        user_id=user.id,
        created_at=now,
        expires_at=expires_at,
    )
    db.session.add(session)
    db.session.commit()
    return jsonify({
        'access_token': token,
        'token_type': 'Bearer',
        'expires_at': expires_at.isoformat(),
        'user': user.to_dict(),
    })


@app.get('/api/auth/me')
def current_auth_user():
    return jsonify(g.auth_user.to_dict())


@app.post('/api/auth/logout')
def logout():
    db.session.delete(g.auth_session)
    db.session.commit()
    return '', 204


@app.route('/api/auth/users', methods=['GET', 'POST'])
def auth_users():
    if request.method == 'GET':
        users = AuthUser.query.order_by(AuthUser.username).all()
        return jsonify([user.to_dict() for user in users])

    payload = request.get_json(silent=True) or {}
    try:
        username = _normalize_username(payload.get('username'))
        role = payload.get('role', 'viewer')
        if role not in ROLE_LEVELS:
            raise ValueError('Invalid role')
        password_hash = _hash_password(str(payload.get('password') or ''))
    except ValueError as error:
        return jsonify({'error': str(error)}), 400
    if AuthUser.query.filter_by(username=username).first() is not None:
        return jsonify({'error': 'Username already exists'}), 409
    now = _utc_now()
    user = AuthUser(
        username=username,
        password_hash=password_hash,
        role=role,
        auth_enabled=bool(payload.get('auth_enabled', True)),
        created_at=now,
        updated_at=now,
    )
    db.session.add(user)
    db.session.commit()
    return jsonify(user.to_dict()), 201


@app.put('/api/auth/users/<int:user_id>')
def update_auth_user(user_id):
    user = db.session.get(AuthUser, user_id)
    if user is None:
        return jsonify({'error': 'Authentication user not found'}), 404
    payload = request.get_json(silent=True) or {}
    try:
        if 'username' in payload:
            username = _normalize_username(payload['username'])
            duplicate = AuthUser.query.filter(
                AuthUser.username == username,
                AuthUser.id != user.id,
            ).first()
            if duplicate is not None:
                return jsonify({'error': 'Username already exists'}), 409
            user.username = username
        if 'role' in payload:
            if payload['role'] not in ROLE_LEVELS:
                raise ValueError('Invalid role')
            user.role = payload['role']
        if 'password' in payload and payload['password']:
            user.password_hash = _hash_password(str(payload['password']))
        if 'auth_enabled' in payload:
            user.auth_enabled = bool(payload['auth_enabled'])
    except ValueError as error:
        return jsonify({'error': str(error)}), 400
    user.updated_at = _utc_now()
    AuthSession.query.filter_by(user_id=user.id).delete()
    db.session.commit()
    return jsonify(user.to_dict())


@app.cli.command('list-auth-users')
def list_auth_users_command():
    for user in AuthUser.query.order_by(AuthUser.username):
        click.echo(f'{user.id}\t{user.username}\t{user.role}\t{user.auth_enabled}')


@app.cli.command('set-auth-user')
@click.argument('username')
@click.option('--role', type=click.Choice(tuple(ROLE_LEVELS)), default='admin')
@click.password_option(confirmation_prompt=True)
def set_auth_user_command(username, role, password):
    normalized = _normalize_username(username)
    password_hash = _hash_password(password)
    now = _utc_now()
    user = AuthUser.query.filter_by(username=normalized).first()
    if user is None:
        user = AuthUser(
            username=normalized,
            created_at=now,
        )
        db.session.add(user)
    user.password_hash = password_hash
    user.role = role
    user.auth_enabled = True
    user.updated_at = now
    db.session.flush()
    AuthSession.query.filter_by(user_id=user.id).delete()
    db.session.commit()
    click.echo(f'Authentication enabled for {normalized} with role {role}.')


@app.cli.command('seed-development')
@click.option('--admin-username', default='devadmin', show_default=True)
@click.option(
    '--reset',
    is_flag=True,
    help='Delete all existing DEV data before creating the canonical dataset.',
)
@click.option(
    '--reference-date',
    type=click.DateTime(formats=['%Y-%m-%d']),
    help='Date used to choose the initial cashback month (YYYY-MM-DD).',
)
def seed_development_command(admin_username, reset, reference_date):
    database_name = db.engine.url.database
    if database_name != 'cashflow_dev':
        raise click.ClickException(
            f'Refusing to seed database {database_name!r}; expected "cashflow_dev".'
        )

    password = None
    if db.session.query(AuthUser).count() == 0:
        password = os.environ.get('CASHFLOW_DEV_ADMIN_PASSWORD')
        if password is None:
            password = click.prompt(
                'DEV admin password',
                hide_input=True,
                confirmation_prompt=True,
            )

    from development_seed import SeedDataExistsError, seed_development_data

    try:
        counts = seed_development_data(
            admin_username,
            password,
            reset=reset,
            reference_date=reference_date.date() if reference_date else None,
        )
    except (SeedDataExistsError, ValueError) as error:
        raise click.ClickException(str(error)) from error

    click.echo(
        'Development dataset created: '
        + ', '.join(f'{name}={value}' for name, value in counts.items())
    )

# Роуты для банков
@app.route('/api/banks', methods=['GET', 'POST'])
def banks():
    if request.method == 'POST':
        data = request.json
        if 'name' not in data:
            return jsonify({'error': 'Bank name is required'}), 400

        bank = Bank(
            name=data['name'],
            description=data.get('description')
        )
        db.session.add(bank)
        db.session.commit()
        return jsonify(bank.to_dict()), 201

    banks = Bank.query.all()
    return jsonify([bank.to_dict() for bank in banks])


# Роуты для владельцев карт
@app.route('/api/users', methods=['GET', 'POST'])
def users():
    if request.method == 'POST':
        data = request.json
        if 'name' not in data:
            return jsonify({'error': 'Name is required'}), 400

        user = CardUser(
            name=data['name']
        )
        db.session.add(user)
        db.session.commit()
        return jsonify(user.to_dict()), 201

    users = CardUser.query.all()
    return jsonify([user.to_dict() for user in users])


# Роуты для банковских карт
@app.route('/api/cards', methods=['GET', 'POST'])
def cards():
    if request.method == 'POST':
        data = request.json

        # Валидация обязательных полей
        required_fields = ['payment_system', 'card_type', 'last_four_digits', 'bank_id', 'user_id']
        if not all(field in data for field in required_fields):
            return jsonify({'error': 'Missing required fields'}), 400

        # Проверка формата последних 4 цифр
        if len(data['last_four_digits']) != 4 or not data['last_four_digits'].isdigit():
            return jsonify({'error': 'Last four digits must be exactly 4 digits'}), 400

        # Проверка существования банка и пользователя
        if not db.session.get(Bank, data['bank_id']):
            return jsonify({'error': 'Bank not found'}), 404
        if not db.session.get(CardUser, data['user_id']):
            return jsonify({'error': 'User not found'}), 404

        # Создание новой карты
        new_card = BankCard(
            payment_system=data['payment_system'],
            card_type=data['card_type'],
            last_four_digits=data['last_four_digits'],
            bank_id=data['bank_id'],
            user_id=data['user_id'],
            is_active=data.get('is_active', True),
            max_cashback_categories=data.get('max_cashback_categories', 4)
        )

        db.session.add(new_card)
        db.session.commit()
        return jsonify(new_card.to_dict()), 201

    # GET запрос - список всех карт
    cards = db.session.execute(select(BankCard)).scalars().all()
    return jsonify([card.to_dict() for card in cards])


@app.route('/api/cards/<int:card_id>', methods=['GET', 'PUT', 'DELETE'])
def card_detail(card_id):
    card = db.session.get(BankCard, card_id)
    if not card:
        return jsonify({'error': 'Card not found'}), 404

    if request.method == 'GET':
        return jsonify(card.to_dict())

    elif request.method == 'PUT':
        data = request.json

        # Валидация обновляемых полей
        if 'last_four_digits' in data:
            if len(data['last_four_digits']) != 4 or not data['last_four_digits'].isdigit():
                return jsonify({'error': 'Last four digits must be exactly 4 digits'}), 400
            card.last_four_digits = data['last_four_digits']

        if 'bank_id' in data:
            if not db.session.get(Bank, data['bank_id']):
                return jsonify({'error': 'Bank not found'}), 404
            card.bank_id = data['bank_id']

        if 'user_id' in data:
            if not db.session.get(CardUser, data['user_id']):
                return jsonify({'error': 'User not found'}), 404
            card.user_id = data['user_id']

        if 'payment_system' in data:
            card.payment_system = data['payment_system']

        if 'card_type' in data:
            card.card_type = data['card_type']

        if 'is_active' in data:
            card.is_active = data['is_active']

        if 'max_cashback_categories' in data:
            card.max_cashback_categories = data['max_cashback_categories']

        db.session.commit()
        return jsonify(card.to_dict())

    elif request.method == 'DELETE':
        db.session.delete(card)
        db.session.commit()
        return jsonify({'message': 'Card deleted successfully'})


# Роуты для категорий кешбека
@app.route('/api/cashback', methods=['GET', 'POST'])
def cashback_categories():
    if request.method == 'POST':
        data = request.json

        required_fields = ['name', 'start_date', 'end_date', 'cashback_percent', 'card_id']
        if not all(field in data for field in required_fields):
            return jsonify({'error': 'Missing required fields'}), 400

        if not BankCard.query.get(data['card_id']):
            return jsonify({'error': 'Card not found'}), 404

        try:
            start_date = datetime.fromisoformat(data['start_date'])
            end_date = datetime.fromisoformat(data['end_date'])
        except ValueError:
            return jsonify({'error': 'Invalid date format. Use ISO format'}), 400

        if start_date >= end_date:
            return jsonify({'error': 'End date must be after start date'}), 400

        new_category = CashbackCategory(
            name=data['name'],
            start_date=start_date,
            end_date=end_date,
            cashback_percent=data['cashback_percent'],
            card_id=data['card_id'],
            is_selected=data.get('is_selected', False),
            description=data.get('description'),
            category_type=data.get('category_type', 'standard'),
            is_selection_locked=data.get('is_selection_locked', False),
            max_cashback_amount=data.get('max_cashback_amount'),
            min_purchase_amount=data.get('min_purchase_amount')
        )

        db.session.add(new_category)
        db.session.commit()
        return jsonify(new_category.to_dict()), 201

    categories = CashbackCategory.query.all()
    return jsonify([category.to_dict() for category in categories])


@app.route('/api/cashback/<int:category_id>', methods=['GET', 'PUT', 'DELETE'])
def cashback_category_detail(category_id):
    category = CashbackCategory.query.get_or_404(category_id)

    if request.method == 'GET':
        return jsonify(category.to_dict())

    elif request.method == 'PUT':
        data = request.json
        # Editing the offer cannot preserve proof for different bank terms.
        if any(key in data and data[key] != category.to_dict().get(key) for key in (
            'name', 'start_date', 'end_date', 'cashback_percent', 'card_id', 'category_type',
        )):
            category.is_bank_confirmed = False

        if 'name' in data:
            category.name = data['name']

        if 'start_date' in data:
            try:
                category.start_date = datetime.fromisoformat(data['start_date'])
            except ValueError:
                return jsonify({'error': 'Invalid start date format'}), 400

        if 'end_date' in data:
            try:
                category.end_date = datetime.fromisoformat(data['end_date'])
            except ValueError:
                return jsonify({'error': 'Invalid end date format'}), 400

        if 'cashback_percent' in data:
            category.cashback_percent = data['cashback_percent']

        if 'is_selected' in data:
            if category.is_selected != data['is_selected']:
                category.is_bank_confirmed = False
            category.is_selected = data['is_selected']

        if 'description' in data:
            category.description = data['description']

        if 'category_type' in data:
            category.category_type = data['category_type']

        if 'is_selection_locked' in data:
            category.is_selection_locked = data['is_selection_locked']

        if 'max_cashback_amount' in data:
            category.max_cashback_amount = data['max_cashback_amount']

        if 'min_purchase_amount' in data:
            category.min_purchase_amount = data['min_purchase_amount']

        if 'card_id' in data:
            if not BankCard.query.get(data['card_id']):
                return jsonify({'error': 'Card not found'}), 404
            category.card_id = data['card_id']

        db.session.commit()
        return jsonify(category.to_dict())

    elif request.method == 'DELETE':
        db.session.delete(category)
        db.session.commit()
        return jsonify({'message': 'Cashback category deleted successfully'}), 200


MCC_PATTERN = re.compile(r'^\d{4}$')
MCC_VALIDITY_CONFIDENCE = {'exact', 'inferred', 'unknown'}
MCC_COMPLETENESS = {'exact_mcc', 'partial_mcc', 'text_only', 'unknown'}
MCC_SOURCE_TYPES = {'public_page', 'pdf', 'api', 'browser', 'manual_verified'}


def _canonical_json(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), sort_keys=True)


def _sha256_json(value):
    return hashlib.sha256(_canonical_json(value).encode('utf-8')).hexdigest()


def _parse_rule_datetime(value, field_name):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f'{field_name} must be an ISO date or datetime')
    candidate = value.strip()
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}', candidate):
        candidate += 'T00:00:00+00:00'
    try:
        parsed = datetime.fromisoformat(candidate.replace('Z', '+00:00'))
    except ValueError as error:
        raise ValueError(f'{field_name} must be an ISO date or datetime') from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _iso_datetime(value):
    return _as_utc(value).isoformat() if value is not None else None


def _validate_mcc_list(value, field_name):
    if value is None:
        return []
    if not isinstance(value, list):
        raise ValueError(f'{field_name} must be an array')
    result = []
    for item in value:
        code = str(item)
        if not MCC_PATTERN.fullmatch(code):
            raise ValueError(f'{field_name} contains invalid MCC: {item!r}')
        if code not in result:
            result.append(code)
    return sorted(result)


def _normalize_rule_conditions(value, field_name):
    if value is None:
        return []
    if not isinstance(value, list):
        raise ValueError(f'{field_name} must be an array')
    result = []
    for item in value:
        if not isinstance(item, dict):
            raise ValueError(f'{field_name} entries must be objects')
        kind = str(item.get('kind') or '').strip()
        original_text = str(item.get('originalText') or '').strip()
        if not kind or not original_text:
            raise ValueError(f'{field_name} entries require kind and originalText')
        result.append({
            'kind': kind,
            'operator': item.get('operator'),
            'value': item.get('value'),
            'originalText': original_text,
        })
    return result


def _resolve_rules_bank(bank_id):
    if isinstance(bank_id, int) and not isinstance(bank_id, bool):
        return db.session.get(Bank, bank_id)
    if isinstance(bank_id, str):
        bank_name = BANK_IMPORT_NAMES.get(bank_id, bank_id)
        return Bank.query.filter_by(name=bank_name).first()
    return None


def _normalize_mcc_snapshot(document):
    if not isinstance(document, dict):
        raise ValueError('A bank MCC rules snapshot is required')
    if document.get('schemaVersion') != 1 or document.get('kind') != 'bank_mcc_rules_snapshot':
        raise ValueError('Unsupported bank MCC rules snapshot')

    bank = _resolve_rules_bank(document.get('bankId'))
    if bank is None:
        raise LookupError('Bank not found')

    program_key = str(document.get('programKey') or '').strip()
    program_name = str(document.get('programName') or program_key).strip()
    if not program_key or not program_name:
        raise ValueError('programKey is required')

    validity = document.get('validity') or {}
    valid_from = _parse_rule_datetime(validity.get('from'), 'validity.from')
    valid_to_value = validity.get('to')
    valid_to = (
        _parse_rule_datetime(valid_to_value, 'validity.to')
        if valid_to_value is not None
        else None
    )
    if valid_to is not None and valid_to <= valid_from:
        raise ValueError('validity.to must be after validity.from')
    confidence = validity.get('confidence', 'unknown')
    if confidence not in MCC_VALIDITY_CONFIDENCE:
        raise ValueError('Invalid validity.confidence')

    completeness = document.get('completeness', 'unknown')
    if completeness not in MCC_COMPLETENESS:
        raise ValueError('Invalid completeness')

    source = document.get('source') or {}
    source_type = source.get('type')
    if source_type not in MCC_SOURCE_TYPES:
        raise ValueError('Invalid source.type')
    collected_at = _parse_rule_datetime(document.get('collectedAt'), 'collectedAt')
    published_at = source.get('publishedAt')
    if published_at is not None:
        published_at = _parse_rule_datetime(published_at, 'source.publishedAt')

    global_excluded = _validate_mcc_list(
        document.get('globalExcludedMcc'),
        'globalExcludedMcc',
    )
    categories = document.get('categories')
    if not isinstance(categories, list):
        raise ValueError('categories must be an array')
    normalized_categories = []
    seen_keys = set()
    for index, item in enumerate(categories):
        if not isinstance(item, dict):
            raise ValueError(f'categories[{index}] must be an object')
        source_external_id = item.get('sourceId')
        source_key = str(item.get('sourceKey') or source_external_id or '').strip()
        name = str(item.get('name') or '').strip()
        if not source_key or not name:
            raise ValueError(f'categories[{index}] requires sourceKey/sourceId and name')
        if source_key in seen_keys:
            raise ValueError(f'Duplicate category source key: {source_key}')
        seen_keys.add(source_key)
        included = _validate_mcc_list(item.get('includedMcc'), f'categories[{index}].includedMcc')
        excluded = _validate_mcc_list(item.get('excludedMcc'), f'categories[{index}].excludedMcc')
        overlap = sorted(set(included) & set(excluded))
        if overlap:
            raise ValueError(f'Category {source_key} both includes and excludes MCC {overlap[0]}')
        category_completeness = item.get('completeness', completeness)
        if category_completeness not in MCC_COMPLETENESS:
            raise ValueError(f'Invalid completeness for category {source_key}')
        normalized_categories.append({
            'sourceExternalId': str(source_external_id) if source_external_id is not None else None,
            'sourceKey': source_key,
            'name': name,
            'description': item.get('description'),
            'includedMcc': included,
            'excludedMcc': excluded,
            'conditions': _normalize_rule_conditions(
                item.get('conditions'),
                f'categories[{index}].conditions',
            ),
            'completeness': category_completeness,
        })

    normalized = {
        'bankId': bank.id,
        'programKey': program_key,
        'programName': program_name,
        'productScope': document.get('productScope'),
        'validity': {
            'from': _iso_datetime(valid_from),
            'to': _iso_datetime(valid_to),
            'confidence': confidence,
        },
        'completeness': completeness,
        'globalExcludedMcc': global_excluded,
        'conditions': _normalize_rule_conditions(document.get('conditions'), 'conditions'),
        'categories': sorted(normalized_categories, key=lambda item: item['sourceKey']),
    }
    return {
        'bank': bank,
        'normalized': normalized,
        'valid_from': valid_from,
        'valid_to': valid_to,
        'collected_at': collected_at,
        'source': source,
        'source_type': source_type,
        'source_published_at': published_at,
    }


def _ensure_mcc_codes(codes):
    for code in sorted(set(codes)):
        if db.session.get(MccCode, code) is None:
            db.session.add(MccCode(code=code))


def _revision_to_dict(revision, include_rules=True):
    program = db.session.get(BankCashbackProgram, revision.program_id)
    snapshot = db.session.get(RuleSourceSnapshot, revision.source_snapshot_id)
    result = {
        'id': revision.id,
        'bank_id': program.bank_id,
        'program': {
            'id': program.id,
            'source_key': program.source_key,
            'name': program.name,
            'product_scope': program.product_scope,
        },
        'valid_from': _iso_datetime(revision.valid_from),
        'valid_to': _iso_datetime(revision.valid_to),
        'validity_confidence': revision.validity_confidence,
        'recorded_at': _iso_datetime(revision.recorded_at),
        'last_seen_at': _iso_datetime(revision.last_seen_at),
        'published_recorded_at': _iso_datetime(revision.published_recorded_at),
        'superseded_at': _iso_datetime(revision.superseded_at),
        'completeness': revision.completeness,
        'status': revision.status,
        'source': {
            'type': snapshot.source_type,
            'url': snapshot.source_url,
            'fetched_at': _iso_datetime(snapshot.fetched_at),
            'published_at': _iso_datetime(snapshot.published_at),
            'content_hash': snapshot.content_hash,
            'parser_name': snapshot.parser_name,
            'parser_version': snapshot.parser_version,
        },
    }
    if not include_rules:
        return result

    global_exclusions = BankProgramExclusion.query.filter_by(
        rule_revision_id=revision.id,
    ).order_by(BankProgramExclusion.mcc_code).all()
    program_conditions = BankRuleCondition.query.filter_by(
        rule_revision_id=revision.id,
        category_revision_id=None,
    ).order_by(BankRuleCondition.id).all()
    category_revisions = (
        db.session.query(BankCategoryRevision, BankCategory)
        .join(BankCategory, BankCategory.id == BankCategoryRevision.bank_category_id)
        .filter(BankCategoryRevision.rule_revision_id == revision.id)
        .order_by(BankCategoryRevision.original_name, BankCategory.id)
        .all()
    )
    categories = []
    for category_revision, category in category_revisions:
        mcc_rules = BankCategoryMccRule.query.filter_by(
            category_revision_id=category_revision.id,
        ).order_by(BankCategoryMccRule.mcc_code).all()
        conditions = BankRuleCondition.query.filter_by(
            category_revision_id=category_revision.id,
        ).order_by(BankRuleCondition.id).all()
        source_payload = category_revision.source_payload or {}
        categories.append({
            'id': category.id,
            'source_key': category.source_key,
            'source_external_id': category.source_external_id,
            'name': category_revision.original_name,
            'description': category_revision.original_description,
            'completeness': source_payload.get('completeness', revision.completeness),
            'included_mcc': [rule.mcc_code for rule in mcc_rules if rule.effect == 'include'],
            'excluded_mcc': [rule.mcc_code for rule in mcc_rules if rule.effect == 'exclude'],
            'conditions': [
                {
                    'kind': condition.kind,
                    'operator': condition.operator,
                    'value': condition.value,
                    'original_text': condition.original_text,
                }
                for condition in conditions
            ],
        })
    result.update({
        'global_excluded_mcc': [item.mcc_code for item in global_exclusions],
        'conditions': [
            {
                'kind': condition.kind,
                'operator': condition.operator,
                'value': condition.value,
                'original_text': condition.original_text,
            }
            for condition in program_conditions
        ],
        'categories': categories,
    })
    return result


@app.post('/api/admin/mcc-rule-snapshots')
def create_mcc_rule_snapshot():
    document = (request.get_json(silent=True) or {}).get('document')
    try:
        parsed = _normalize_mcc_snapshot(document)
        normalized = parsed['normalized']
        bank = parsed['bank']
        program = BankCashbackProgram.query.filter_by(
            bank_id=bank.id,
            source_key=normalized['programKey'],
        ).first()
        if program is None:
            program = BankCashbackProgram(
                bank_id=bank.id,
                source_key=normalized['programKey'],
                name=normalized['programName'],
                product_scope=normalized['productScope'],
            )
            db.session.add(program)
            db.session.flush()
        else:
            program.name = normalized['programName']
            program.product_scope = normalized['productScope']

        normalized_hash = _sha256_json(normalized)
        existing = BankRuleRevision.query.filter_by(
            program_id=program.id,
            normalized_hash=normalized_hash,
        ).first()
        if existing is not None:
            if _as_utc(parsed['collected_at']) > _as_utc(existing.last_seen_at):
                existing.last_seen_at = parsed['collected_at']
            db.session.commit()
            return jsonify(_revision_to_dict(existing)), 200

        raw_content = _canonical_json(document)
        snapshot_hash = hashlib.sha256(raw_content.encode('utf-8')).hexdigest()
        snapshot = RuleSourceSnapshot.query.filter_by(content_hash=snapshot_hash).first()
        if snapshot is None:
            source = parsed['source']
            snapshot = RuleSourceSnapshot(
                source_type=parsed['source_type'],
                source_url=source.get('url'),
                fetched_at=parsed['collected_at'],
                published_at=parsed['source_published_at'],
                content_hash=snapshot_hash,
                raw_content=raw_content,
                parser_name=source.get('parserName'),
                parser_version=source.get('parserVersion'),
            )
            db.session.add(snapshot)
            db.session.flush()

        now = _utc_now()
        revision = BankRuleRevision(
            program_id=program.id,
            valid_from=parsed['valid_from'],
            valid_to=parsed['valid_to'],
            validity_confidence=normalized['validity']['confidence'],
            recorded_at=now,
            last_seen_at=parsed['collected_at'],
            source_snapshot_id=snapshot.id,
            completeness=normalized['completeness'],
            status='draft',
            normalized_hash=normalized_hash,
        )
        db.session.add(revision)
        db.session.flush()

        all_mcc = list(normalized['globalExcludedMcc'])
        for item in normalized['categories']:
            all_mcc.extend(item['includedMcc'])
            all_mcc.extend(item['excludedMcc'])
        _ensure_mcc_codes(all_mcc)
        db.session.flush()

        for code in normalized['globalExcludedMcc']:
            db.session.add(BankProgramExclusion(
                rule_revision_id=revision.id,
                mcc_code=code,
            ))
        for condition in normalized['conditions']:
            db.session.add(BankRuleCondition(
                rule_revision_id=revision.id,
                kind=condition['kind'],
                operator=condition['operator'],
                value=None if condition['value'] is None else str(condition['value']),
                original_text=condition['originalText'],
            ))
        for item in normalized['categories']:
            category = BankCategory.query.filter_by(
                program_id=program.id,
                source_key=item['sourceKey'],
            ).first()
            if category is None:
                category = BankCategory(
                    program_id=program.id,
                    source_external_id=item['sourceExternalId'],
                    source_key=item['sourceKey'],
                    created_at=now,
                )
                db.session.add(category)
                db.session.flush()
            category_revision = BankCategoryRevision(
                rule_revision_id=revision.id,
                bank_category_id=category.id,
                original_name=item['name'],
                original_description=item['description'],
                source_payload={'completeness': item['completeness']},
            )
            db.session.add(category_revision)
            db.session.flush()
            for effect, codes in (
                ('include', item['includedMcc']),
                ('exclude', item['excludedMcc']),
            ):
                for code in codes:
                    db.session.add(BankCategoryMccRule(
                        category_revision_id=category_revision.id,
                        mcc_code=code,
                        effect=effect,
                    ))
            for condition in item['conditions']:
                db.session.add(BankRuleCondition(
                    rule_revision_id=revision.id,
                    category_revision_id=category_revision.id,
                    kind=condition['kind'],
                    operator=condition['operator'],
                    value=None if condition['value'] is None else str(condition['value']),
                    original_text=condition['originalText'],
                ))
        db.session.commit()
        return jsonify(_revision_to_dict(revision)), 201
    except LookupError as error:
        db.session.rollback()
        return jsonify({'error': str(error)}), 404
    except ValueError as error:
        db.session.rollback()
        return jsonify({'error': str(error)}), 400
    except Exception:
        db.session.rollback()
        raise


@app.post('/api/admin/mcc-rule-revisions/<int:revision_id>/publish')
def publish_mcc_rule_revision(revision_id):
    revision = db.session.get(BankRuleRevision, revision_id)
    if revision is None:
        return jsonify({'error': 'MCC rule revision not found'}), 404
    if revision.status == 'published':
        return jsonify(_revision_to_dict(revision))
    if revision.status != 'draft':
        return jsonify({'error': 'Only draft revisions can be published'}), 409

    now = _utc_now()
    same_start_revisions = BankRuleRevision.query.filter(
        BankRuleRevision.program_id == revision.program_id,
        BankRuleRevision.status == 'published',
        BankRuleRevision.superseded_at.is_(None),
        BankRuleRevision.valid_from == revision.valid_from,
    ).all()
    for previous in same_start_revisions:
        previous.superseded_at = now
    revision.status = 'published'
    revision.published_recorded_at = now
    db.session.commit()
    return jsonify(_revision_to_dict(revision))


@app.get('/api/admin/mcc-rule-revisions')
def list_mcc_rule_revisions():
    query = BankRuleRevision.query.join(
        BankCashbackProgram,
        BankCashbackProgram.id == BankRuleRevision.program_id,
    )
    bank_id = request.args.get('bank_id', type=int)
    if bank_id is not None:
        if db.session.get(Bank, bank_id) is None:
            return jsonify({'error': 'Bank not found'}), 404
        query = query.filter(BankCashbackProgram.bank_id == bank_id)
    program_key = request.args.get('program_key')
    if program_key:
        query = query.filter(BankCashbackProgram.source_key == program_key)
    revisions = query.order_by(
        BankRuleRevision.recorded_at.desc(),
        BankRuleRevision.id.desc(),
    ).all()
    return jsonify([_revision_to_dict(revision) for revision in revisions])


@app.post('/api/admin/banks/<int:bank_id>/mcc-rules/auto-import')
def auto_import_bank_mcc_rules(bank_id):
    if db.session.get(Bank, bank_id) is None:
        return jsonify({'error': 'Bank not found'}), 404
    return jsonify({
        'error': 'Automatic MCC source is not configured for this bank yet',
        'code': 'automatic_source_not_configured',
    }), 501


def _rules_revision_query(program_id, as_of, known_at=None):
    query = BankRuleRevision.query.filter(
        BankRuleRevision.program_id == program_id,
        BankRuleRevision.status == 'published',
        BankRuleRevision.valid_from <= as_of,
        db.or_(BankRuleRevision.valid_to.is_(None), BankRuleRevision.valid_to > as_of),
    )
    if known_at is not None:
        query = query.filter(
            BankRuleRevision.published_recorded_at <= known_at,
            db.or_(
                BankRuleRevision.superseded_at.is_(None),
                BankRuleRevision.superseded_at > known_at,
            ),
        )
    return query.order_by(
        BankRuleRevision.valid_from.desc(),
        BankRuleRevision.published_recorded_at.desc(),
        BankRuleRevision.id.desc(),
    ).first()


@app.get('/api/mcc/<string:code>')
def get_mcc_code(code):
    if not MCC_PATTERN.fullmatch(code):
        return jsonify({'error': 'MCC must contain exactly four digits'}), 400
    mcc = db.session.get(MccCode, code)
    if mcc is None:
        return jsonify({'error': 'MCC not found'}), 404
    return jsonify(mcc.to_dict())


@app.get('/api/banks/<int:bank_id>/mcc-rules')
def get_bank_mcc_rules(bank_id):
    bank = db.session.get(Bank, bank_id)
    if bank is None:
        return jsonify({'error': 'Bank not found'}), 404
    try:
        as_of = _parse_rule_datetime(
            request.args.get('as_of') or _utc_now().isoformat(),
            'as_of',
        )
        known_at_value = request.args.get('known_at')
        known_at = (
            _parse_rule_datetime(known_at_value, 'known_at')
            if known_at_value
            else None
        )
    except ValueError as error:
        return jsonify({'error': str(error)}), 400

    programs_query = BankCashbackProgram.query.filter_by(bank_id=bank.id)
    program_key = request.args.get('program_key')
    if program_key:
        programs_query = programs_query.filter_by(source_key=program_key)
    revisions = []
    for program in programs_query.order_by(BankCashbackProgram.id):
        revision = _rules_revision_query(program.id, as_of, known_at)
        if revision is not None:
            revisions.append(_revision_to_dict(revision))
    return jsonify({
        'bank': bank.to_dict(),
        'as_of': _iso_datetime(as_of),
        'known_at': _iso_datetime(known_at),
        'rules': revisions,
    })


@app.get('/api/banks/<int:bank_id>/categories/<int:category_id>/mcc-rules')
def get_bank_category_mcc_rules(bank_id, category_id):
    category = db.session.get(BankCategory, category_id)
    program = (
        db.session.get(BankCashbackProgram, category.program_id)
        if category is not None
        else None
    )
    if category is None or program is None or program.bank_id != bank_id:
        return jsonify({'error': 'Bank category not found'}), 404
    try:
        as_of = _parse_rule_datetime(
            request.args.get('as_of') or _utc_now().isoformat(),
            'as_of',
        )
    except ValueError as error:
        return jsonify({'error': str(error)}), 400
    revision = _rules_revision_query(program.id, as_of)
    if revision is None:
        return jsonify({'error': 'MCC rules not found for the requested date'}), 404
    payload = _revision_to_dict(revision)
    selected = next(
        (item for item in payload['categories'] if item['id'] == category.id),
        None,
    )
    if selected is None:
        return jsonify({'error': 'Category has no rules for the requested date'}), 404
    return jsonify({
        'bank_id': bank_id,
        'program': payload['program'],
        'valid_from': payload['valid_from'],
        'valid_to': payload['valid_to'],
        'validity_confidence': payload['validity_confidence'],
        'completeness': payload['completeness'],
        'source': payload['source'],
        'global_excluded_mcc': payload['global_excluded_mcc'],
        'program_conditions': payload['conditions'],
        'category': selected,
    })


BANK_IMPORT_NAMES = {
    'tbank': 'Т-Банк',
    'yandex': 'Яндекс',
    'alfa': 'Альфа',
    'sber': 'Сбер',
    'ozon': 'Озон',
    'vtb': 'ВТБ',
}

RUSSIAN_MONTHS = {
    'января': 1,
    'февраля': 2,
    'марта': 3,
    'апреля': 4,
    'мая': 5,
    'июня': 6,
    'июля': 7,
    'августа': 8,
    'сентября': 9,
    'октября': 10,
    'ноября': 11,
    'декабря': 12,
}


def _parse_import_datetime(value):
    if not isinstance(value, str):
        raise ValueError('generatedAt must be an ISO date')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone(timedelta(hours=3)))


def _next_month(value):
    if value.month == 12:
        return datetime(value.year + 1, 1, 1)
    return datetime(value.year, value.month + 1, 1)


def _category_period(generated_at, expires_in_label):
    start = datetime(generated_at.year, generated_at.month, 1)
    default_end = _next_month(start)
    if not expires_in_label:
        return start, default_end

    label = str(expires_in_label).strip().lower()
    days_match = re.search(r'ещ[её]\s+(\d+)\s+д', label)
    if days_match:
        end = datetime(
            generated_at.year,
            generated_at.month,
            generated_at.day,
        ) + timedelta(days=int(days_match.group(1)))
        return start, default_end if end <= start else end

    date_match = re.search(r'до\s+(\d{1,2})\s+([а-яё]+)', label)
    if date_match and date_match.group(2) in RUSSIAN_MONTHS:
        month = RUSSIAN_MONTHS[date_match.group(2)]
        year = generated_at.year
        end_date = datetime(year, month, int(date_match.group(1)))
        if end_date.date() < generated_at.date():
            end_date = end_date.replace(year=year + 1)
        return start, end_date + timedelta(days=1)

    return start, default_end


def _resolve_import_card(bank_id, user_id, explicit_card_ids):
    bank_name = BANK_IMPORT_NAMES.get(bank_id)
    if bank_name is None:
        return None, f'Unsupported bank: {bank_id}'

    bank = Bank.query.filter_by(name=bank_name).first()
    if bank is None:
        return None, f'Bank is not configured: {bank_name}'

    explicit_id = explicit_card_ids.get(bank_id)
    query = BankCard.query.filter_by(bank_id=bank.id, user_id=user_id)
    if explicit_id is not None:
        card = query.filter_by(id=explicit_id).first()
        if card is None:
            return None, f'Card {explicit_id} does not belong to user {user_id} and {bank_name}'
        return card, None

    cards = query.filter_by(user_id=user_id, is_active=True).all()
    if len(cards) != 1:
        return None, f'Expected one active {bank_name} card for user {user_id}, found {len(cards)}'
    return cards[0], None


def _selection_is_locked(bank_result, categories):
    selection = bank_result.get('selection') or {}
    explicit_value = selection.get('isLocked')
    if isinstance(explicit_value, bool):
        return explicit_value

    return False


def _normalize_import_category_type(value):
    return value if value in ('standard', 'stackable_bonus', 'task_bonus') else 'standard'


def _amount_value(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


def _amount_from_match(match):
    if match is None:
        return None
    return float(re.sub(r'[\s\u00a0\u202f]', '', match.group(1)).replace(',', '.'))


def _extract_cashback_amounts(imported):
    max_amount = _amount_value(imported.get('maxCashbackAmount'))
    min_amount = _amount_value(imported.get('minPurchaseAmount'))
    source_text = f"{imported.get('subtitle') or ''}\n{imported.get('description') or ''}"
    amount = r'(\d[\d\s\u00a0\u202f]*(?:[.,]\d+)?)'
    currency = r'(?:₽|руб(?:ль|ля|лей)?\.?|р\.)'

    if max_amount is None:
        max_patterns = (
            rf'к[еэ]шб[еэ]к\s+до\s+{amount}\s*{currency}',
            rf'лимит\s+к[еэ]шб[еэ]ка[^\d]{{0,40}}{amount}\s*{currency}',
        )
        for pattern in max_patterns:
            max_amount = _amount_from_match(re.search(pattern, source_text, re.IGNORECASE))
            if max_amount is not None:
                break

    if min_amount is None:
        min_patterns = (
            rf'(?:покупк[а-яё]*|заказ[а-яё]*|чек[а-яё]*)[^.\n]{{0,60}}?\sот\s+{amount}\s*{currency}',
            rf'минимальн[а-яё]*\s+(?:сумм[а-яё]*|чек[а-яё]*)[^\d]{{0,30}}{amount}\s*{currency}',
        )
        for pattern in min_patterns:
            min_amount = _amount_from_match(re.search(pattern, source_text, re.IGNORECASE))
            if min_amount is not None:
                break

    return max_amount, min_amount


def _clean_category_description(bank_id, description):
    if not isinstance(description, str) or not description.strip():
        return None

    amount = r'\d[\d\s\u00a0\u202f]*(?:[.,]\d+)?'
    currency = r'(?:₽|руб(?:ль|ля|лей)?\.?|р\.)'
    cleaned = re.sub(
        rf'(?:к[еэ]шб[еэ]к\s+до\s+{amount}\s*{currency}'
        rf'|лимит\s+к[еэ]шб[еэ]ка[^\d]{{0,40}}{amount}\s*{currency})\.?\s*',
        '',
        description,
        flags=re.IGNORECASE,
    )
    if bank_id == 'vtb':
        cleaned = re.sub(
            r'МСС\s*[—–-]\s*это\s+код\s+вида\s+деятельности\s+продавца\.\s*'
            r'По\s+нему\s+банк\s+определяет\s+категорию\s+покупки\s+для\s+'
            r'расчета\s+кешбэка\.?\s*',
            '',
            cleaned,
            flags=re.IGNORECASE,
        )

    lines = [re.sub(r'\s+', ' ', line).strip() for line in cleaned.splitlines()]
    cleaned = '\n'.join(line for line in lines if line)
    return cleaned or None


@app.route('/api/cashback/import', methods=['POST'])
def import_cashback():
    payload = request.get_json(silent=True) or {}
    document = payload.get('document')
    user_id = payload.get('user_id')
    explicit_card_ids = payload.get('card_ids') or {}

    if not isinstance(document, dict):
        return jsonify({'error': 'A cashback import document is required'}), 400
    if document.get('schemaVersion') != 1 or not isinstance(document.get('banks'), list):
        return jsonify({'error': 'Unsupported cashback import document'}), 400
    if not isinstance(user_id, int) or db.session.get(CardUser, user_id) is None:
        return jsonify({'error': 'A valid user_id is required'}), 400

    try:
        generated_at = _parse_import_datetime(document.get('generatedAt'))
    except (TypeError, ValueError) as error:
        return jsonify({'error': str(error)}), 400

    created = 0
    updated = 0
    skipped = []
    imported_banks = []

    try:
        for bank_result in document['banks']:
            bank_id = bank_result.get('bankId')
            categories = bank_result.get('categories')
            if bank_result.get('authenticationStatus') != 'authenticated':
                skipped.append({'bank_id': bank_id, 'reason': 'Bank is not authenticated'})
                continue
            if not isinstance(categories, list):
                skipped.append({'bank_id': bank_id, 'reason': 'Categories are missing'})
                continue

            card, error = _resolve_import_card(bank_id, user_id, explicit_card_ids)
            if error:
                skipped.append({'bank_id': bank_id, 'reason': error})
                continue

            max_selectable = (bank_result.get('selection') or {}).get('maxSelectable')
            selection_locked = _selection_is_locked(bank_result, categories)
            if isinstance(max_selectable, int) and max_selectable > 0:
                card.max_cashback_categories = max_selectable

            bank_count = 0
            selected_standard_count = 0
            # A fresh successful snapshot supersedes previous bank evidence,
            # including categories absent from the new result.
            for existing in CashbackCategory.query.filter(
                CashbackCategory.card_id == card.id,
                CashbackCategory.start_date <= generated_at,
                CashbackCategory.end_date > generated_at,
            ):
                existing.is_bank_confirmed = False
            for imported in categories:
                name = str(imported.get('name') or '').strip()
                percent = imported.get('percent')
                if not name or not isinstance(percent, (int, float)):
                    continue

                category_type = _normalize_import_category_type(imported.get('type'))
                start_date, end_date = _category_period(
                    generated_at,
                    imported.get('expiresInLabel'),
                )
                category = CashbackCategory.query.filter_by(
                    card_id=card.id,
                    name=name,
                    start_date=start_date,
                    category_type=category_type,
                ).first()
                if category is None:
                    category = CashbackCategory(
                        card_id=card.id,
                        name=name,
                        start_date=start_date,
                        category_type=category_type,
                    )
                    db.session.add(category)
                    created += 1
                else:
                    updated += 1

                category.end_date = end_date
                category.cashback_percent = float(percent)
                bank_selected = imported.get('selected') is True
                category.is_bank_confirmed = bank_selected and (
                    imported.get('confirmed') is True or selection_locked
                )
                # Preserve the desired selection until the bank confirms it.
                category.is_selected = bank_selected or bool(category.is_selected)
                category.description = _clean_category_description(
                    bank_id,
                    imported.get('description'),
                )
                (
                    category.max_cashback_amount,
                    category.min_purchase_amount,
                ) = _extract_cashback_amounts(imported)
                category.is_selection_locked = selection_locked
                if category.is_selected and category_type == 'standard':
                    selected_standard_count += 1
                bank_count += 1

            if not isinstance(max_selectable, int) and selected_standard_count > (
                card.max_cashback_categories or 0
            ):
                card.max_cashback_categories = selected_standard_count

            imported_banks.append({
                'bank_id': bank_id,
                'card_id': card.id,
                'categories': bank_count,
                'selection_locked': selection_locked,
            })

        db.session.commit()
    except Exception:
        db.session.rollback()
        raise

    return jsonify({
        'created': created,
        'updated': updated,
        'imported_banks': imported_banks,
        'skipped': skipped,
    })


@app.route('/api/active_cashback', methods=['GET'])
def get_active_cashback():
    today = datetime.now()

    categories = CashbackCategory.query.where(
        CashbackCategory.is_selected == True,
        CashbackCategory.is_bank_confirmed == True,
        CashbackCategory.start_date <= today,
        CashbackCategory.end_date > today

    )
    return jsonify([category.to_dict() for category in categories])


    # SQLAlchemy 2.0 style query with joins
    stmt = (
        select(
            Bank.name.label('bank_name'),
            CardUser.name.label('user_name'),
            BankCard.last_four_digits,
            CashbackCategory.name.label('category_name'),
            CashbackCategory.cashback_percent
        )
        .select_from(BankCard)
        .join(Bank, BankCard.bank_id == Bank.id)
        .join(CardUser, BankCard.user_id == CardUser.id)
        .join(CashbackCategory, CashbackCategory.card_id == BankCard.id)
        .where(
            # BankCard.is_active == True,
            CashbackCategory.is_selected == True,
            # CashbackCategory.start_date <= today,
            # CashbackCategory.end_date >= today
        )
        .order_by(BankCard.id)
    )

    # Execute query and process results
    result = {}
    for row in db.session.execute(stmt):
        card_key = f"{row.bank_name} {row.user_name} ({row.last_four_digits})"

        if card_key not in result:
            result[card_key] = {
                "name": f'{row.bank_name} {row.user_name}',
                "number": row.last_four_digits,
                "categories": []
            }

        result[card_key]["categories"].append({
            "name": row.category_name,
            "percent": row.cashback_percent
        })

    return jsonify(list(result.values()))


PARTNER_RATINGS = {'interesting', 'undecided', 'hidden'}
PARTNER_BENEFIT_KINDS = {'cashback', 'discount', 'other'}
PARTNER_DETAIL_STATUSES = {'complete', 'preview_only', 'error'}


def _parse_partner_datetime(value, field_name, required=False):
    if value in (None, ''):
        if required:
            raise ValueError(f'{field_name} is required')
        return None
    if not isinstance(value, str):
        raise ValueError(f'{field_name} must be an ISO date')
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError as error:
        raise ValueError(f'{field_name} must be an ISO date') from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _json_array(value):
    return value if isinstance(value, list) else []


def _partner_rate_qualifier(rate_label, percent):
    normalized = str(rate_label or '').strip().lower()
    if re.search(r'\bдо\b', normalized):
        return 'up_to'
    if re.search(r'\bот\b', normalized):
        return 'from'
    if isinstance(percent, (int, float)) and not isinstance(percent, bool):
        return 'exact'
    return 'unknown'


def _partner_benefit_kind(raw):
    value = raw.get('offerKind') or raw.get('benefitKind')
    if value in PARTNER_BENEFIT_KINDS:
        return value
    label = str(raw.get('rateLabel') or '').lower()
    if 'скид' in label:
        return 'discount'
    if 'кэшб' in label or 'кешб' in label or raw.get('percent') is not None:
        return 'cashback'
    return 'other'


def _partner_details_status(raw):
    value = raw.get('detailsStatus')
    if value in PARTNER_DETAIL_STATUSES:
        return value
    return 'complete' if raw.get('conditions') else 'preview_only'


def _partner_content(raw):
    content = dict(raw)
    # Collection timestamps describe evidence freshness, not offer contents.
    content.pop('detailCollectedAt', None)
    content.pop('collectedAt', None)
    content.pop('conditionsCollectedAt', None)
    return content


def _partner_limit_from_text(original):
    normalized = original.lower().replace('\u00a0', ' ').replace('\u202f', ' ')
    amount_match = re.search(r'(\d[\d\s]*(?:[.,]\d+)?)', normalized)
    value = None
    if amount_match:
        value = float(amount_match.group(1).replace(' ', '').replace(',', '.'))
    if re.search(r'₽|руб', normalized):
        unit = 'RUB'
    elif re.search(r'бонус', normalized):
        unit = 'bonus'
    elif re.search(r'балл', normalized):
        unit = 'points'
    else:
        unit = 'unknown'
    if re.search(r'покупк|заказ|чек', normalized):
        scope = 'purchase'
    elif re.search(r'месяц', normalized):
        scope = 'month'
    elif re.search(r'акци', normalized):
        scope = 'campaign'
    else:
        scope = 'unknown'
    limit_type = 'minimum_purchase' if re.search(
        r'минимальн|(?:^|\s)от\s+\d',
        normalized,
    ) else 'max_cashback'
    return limit_type, value, unit, scope


def _add_partner_limits(snapshot, raw):
    imported_types = set()
    for original in _json_array(raw.get('limits')):
        if not isinstance(original, str) or not original.strip():
            continue
        limit_type, value, unit, scope = _partner_limit_from_text(original)
        db.session.add(PartnerOfferLimit(
            snapshot_id=snapshot.id,
            limit_type=limit_type,
            value=value,
            unit=unit,
            scope=scope,
            original_text=original.strip(),
        ))
        imported_types.add(limit_type)

    structured = (
        ('max_cashback', raw.get('maxCashbackAmount')),
        ('minimum_purchase', raw.get('minPurchaseAmount')),
    )
    for limit_type, value in structured:
        if limit_type in imported_types:
            continue
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            continue
        db.session.add(PartnerOfferLimit(
            snapshot_id=snapshot.id,
            limit_type=limit_type,
            value=value,
            # The extension contract does not prove whether the amount means
            # rubles, bonuses, or points, so importing it as RUB would lie.
            unit='unknown',
            scope='purchase' if limit_type == 'minimum_purchase' else 'unknown',
            original_text=f'{limit_type}: {value}',
        ))


def _partner_snapshot_to_dict(snapshot):
    limits = PartnerOfferLimit.query.filter_by(snapshot_id=snapshot.id).order_by(
        PartnerOfferLimit.id
    ).all()
    return {
        'id': snapshot.id,
        'collected_at': _as_utc(snapshot.collected_at).isoformat(),
        'details_collected_at': (
            _as_utc(snapshot.details_collected_at).isoformat()
            if snapshot.details_collected_at else None
        ),
        'title': snapshot.title,
        'description': snapshot.description,
        'benefit_kind': snapshot.benefit_kind,
        'rate_value': float(snapshot.rate_value) if snapshot.rate_value is not None else None,
        'rate_qualifier': snapshot.rate_qualifier,
        'rate_label': snapshot.rate_label,
        'starts_at': _as_utc(snapshot.starts_at).isoformat() if snapshot.starts_at else None,
        'ends_at': _as_utc(snapshot.ends_at).isoformat() if snapshot.ends_at else None,
        'validity_label': snapshot.validity_label,
        'validity_precision': snapshot.validity_precision,
        'preview_text': snapshot.preview_text,
        'conditions': snapshot.conditions,
        'steps': json.loads(snapshot.steps_json),
        'links': json.loads(snapshot.links_json),
        'requirements': json.loads(snapshot.requirements_json),
        'details_status': snapshot.details_status,
        'details_error': snapshot.details_error,
        'source_url': snapshot.source_url,
        'icon_url': snapshot.icon_url,
        'artwork_url': snapshot.artwork_url,
        'limits': [
            {
                'type': limit.limit_type,
                'value': float(limit.value) if limit.value is not None else None,
                'unit': limit.unit,
                'scope': limit.scope,
                'original_text': limit.original_text,
            }
            for limit in limits
        ],
    }


def _partner_icon_mime_type(content, content_type):
    declared = (content_type or '').partition(';')[0].strip().lower()
    if declared.startswith('image/'):
        return declared
    if content.startswith(b'\x89PNG\r\n\x1a\n'):
        return 'image/png'
    if content.startswith(b'\xff\xd8\xff'):
        return 'image/jpeg'
    if content.startswith((b'GIF87a', b'GIF89a')):
        return 'image/gif'
    if content.startswith(b'RIFF') and content[8:12] == b'WEBP':
        return 'image/webp'
    if content.lstrip().startswith(b'<svg'):
        return 'image/svg+xml'
    raise ValueError('The partner icon response is not an image')


@lru_cache(maxsize=512)
def _fetch_partner_icon(source_url):
    parsed = urlparse(source_url)
    if parsed.scheme != 'https' or parsed.hostname not in PARTNER_ICON_HOSTS:
        raise ValueError('The partner icon host is not allowed')
    upstream_request = Request(
        source_url,
        headers={
            'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
            'User-Agent': 'CashFlow partner icon proxy/1.0',
        },
    )
    with urlopen(upstream_request, timeout=10) as upstream:
        final_url = urlparse(upstream.geturl())
        if final_url.scheme != 'https' or final_url.hostname not in PARTNER_ICON_HOSTS:
            raise ValueError('The partner icon redirect host is not allowed')
        content = upstream.read(PARTNER_ICON_MAX_BYTES + 1)
        if len(content) > PARTNER_ICON_MAX_BYTES:
            raise ValueError('The partner icon is too large')
        mime_type = _partner_icon_mime_type(
            content,
            upstream.headers.get('Content-Type'),
        )
    return content, mime_type


def _partner_preference(offer_id, auth_user_id):
    return PartnerOfferPreference.query.filter_by(
        offer_id=offer_id,
        auth_user_id=auth_user_id,
    ).first()


def _partner_offer_to_dict(offer, snapshot, auth_user_id, include_details=False):
    preference = _partner_preference(offer.id, auth_user_id)
    bank = db.session.get(Bank, offer.bank_id)
    data = {
        'id': offer.id,
        'bank_id': offer.bank_id,
        'bank_name': bank.name if bank else None,
        'card_user_id': offer.card_user_id,
        'merchant_id': offer.merchant_id,
        'source_key': offer.source_key,
        'is_available': offer.is_available,
        'first_seen_at': _as_utc(offer.first_seen_at).isoformat(),
        'last_seen_at': _as_utc(offer.last_seen_at).isoformat(),
        'preference': preference.rating if preference else 'undecided',
        'snapshot': _partner_snapshot_to_dict(snapshot),
    }
    if snapshot.icon_url:
        data['snapshot']['icon_url'] = url_for(
            'partner_offer_icon',
            offer_id=offer.id,
            _external=True,
        )
    if not include_details:
        data['snapshot'].pop('conditions')
        data['snapshot'].pop('steps')
        data['snapshot'].pop('links')
        data['snapshot'].pop('requirements')
    return data


@app.post('/api/partner-offers/import')
def import_partner_offers():
    payload = request.get_json(silent=True) or {}
    document = payload.get('document')
    card_user_id = payload.get('card_user_id')
    if not isinstance(document, dict) or document.get('schemaVersion') != 1:
        return jsonify({'error': 'A schemaVersion 1 import document is required'}), 400
    if not isinstance(document.get('banks'), list):
        return jsonify({'error': 'The import document must contain banks'}), 400
    if not isinstance(card_user_id, int) or db.session.get(CardUser, card_user_id) is None:
        return jsonify({'error': 'A valid card_user_id is required'}), 400

    complete_bank_ids = payload.get('complete_bank_ids') or []
    if not isinstance(complete_bank_ids, list):
        return jsonify({'error': 'complete_bank_ids must be a list'}), 400
    complete_bank_ids = set(complete_bank_ids)
    counters = {
        'created_offers': 0,
        'updated_offers': 0,
        'created_snapshots': 0,
        'reused_snapshots': 0,
    }
    runs = []
    skipped = []

    try:
        document_collected_at = _parse_partner_datetime(
            document.get('generatedAt'),
            'generatedAt',
            required=True,
        )
        for bank_result in document['banks']:
            if not isinstance(bank_result, dict):
                skipped.append({'bank_id': None, 'reason': 'Invalid bank result'})
                continue
            source_bank_id = bank_result.get('bankId')
            bank_name = BANK_IMPORT_NAMES.get(source_bank_id)
            offers = bank_result.get('extendedOffers')
            if bank_name is None:
                skipped.append({'bank_id': source_bank_id, 'reason': 'Unsupported bank'})
                continue
            bank = Bank.query.filter_by(name=bank_name).first()
            if bank is None:
                skipped.append({'bank_id': source_bank_id, 'reason': 'Bank is not configured'})
                continue
            if not isinstance(offers, list):
                skipped.append({'bank_id': source_bank_id, 'reason': 'extendedOffers are missing'})
                continue

            summary = bank_result.get('extendedSummary') or {}
            collected_at = _parse_partner_datetime(
                summary.get('collectedAt') or bank_result.get('collectedAt'),
                f'{source_bank_id}.collectedAt',
            ) or document_collected_at
            completeness = 'complete' if source_bank_id in complete_bank_ids else (
                'partial' if summary.get('errors') else 'unknown'
            )
            seen_offer_ids = set()
            details_count = 0

            for raw in offers:
                if not isinstance(raw, dict):
                    continue
                source_key = str(raw.get('id') or '').strip()
                title = str(raw.get('name') or '').strip()
                if not source_key or not title:
                    continue
                offer = PartnerOffer.query.filter_by(
                    bank_id=bank.id,
                    card_user_id=card_user_id,
                    source_key=source_key,
                ).first()
                if offer is None:
                    offer = PartnerOffer(
                        bank_id=bank.id,
                        card_user_id=card_user_id,
                        source_key=source_key,
                        source_external_id=source_key,
                        first_seen_at=collected_at,
                        last_seen_at=collected_at,
                        is_available=True,
                    )
                    db.session.add(offer)
                    db.session.flush()
                    counters['created_offers'] += 1
                else:
                    offer.last_seen_at = max(_as_utc(offer.last_seen_at), collected_at)
                    offer.is_available = True
                    offer.unavailable_at = None
                    counters['updated_offers'] += 1

                seen_offer_ids.add(offer.id)
                raw_content = _canonical_json(raw)
                content_hash = _sha256_json(_partner_content(raw))
                snapshot = PartnerOfferSnapshot.query.filter_by(
                    offer_id=offer.id,
                    content_hash=content_hash,
                ).first()
                if snapshot is None:
                    percent = raw.get('percent')
                    if isinstance(percent, bool) or not isinstance(percent, (int, float)):
                        percent = None
                    starts_at = _parse_partner_datetime(raw.get('startDate'), 'startDate')
                    ends_at = _parse_partner_datetime(raw.get('endDate'), 'endDate')
                    details_collected_at = _parse_partner_datetime(
                        raw.get('detailCollectedAt') or raw.get('conditionsCollectedAt'),
                        'detailCollectedAt',
                    )
                    details_status = _partner_details_status(raw)
                    snapshot = PartnerOfferSnapshot(
                        offer_id=offer.id,
                        collected_at=collected_at,
                        details_collected_at=details_collected_at,
                        title=title,
                        description=raw.get('description'),
                        benefit_kind=_partner_benefit_kind(raw),
                        rate_value=percent,
                        rate_qualifier=_partner_rate_qualifier(raw.get('rateLabel'), percent),
                        rate_label=raw.get('rateLabel'),
                        starts_at=starts_at,
                        ends_at=ends_at,
                        validity_label=(
                            raw.get('validityLabel') or raw.get('expirationLabel')
                        ),
                        validity_precision='exact' if starts_at or ends_at else 'unknown',
                        preview_text=raw.get('previewText'),
                        conditions=raw.get('conditions'),
                        steps_json=_canonical_json(_json_array(raw.get('steps'))),
                        links_json=_canonical_json(_json_array(raw.get('links'))),
                        requirements_json=_canonical_json(_json_array(raw.get('requirements'))),
                        details_status=details_status,
                        details_error=raw.get('detailsError'),
                        source_url=raw.get('sourceUrl'),
                        icon_url=raw.get('iconUrl'),
                        artwork_url=raw.get('artworkUrl'),
                        raw_json=raw_content,
                        content_hash=content_hash,
                    )
                    db.session.add(snapshot)
                    db.session.flush()
                    _add_partner_limits(snapshot, raw)
                    counters['created_snapshots'] += 1
                else:
                    snapshot.collected_at = max(
                        _as_utc(snapshot.collected_at),
                        collected_at,
                    )
                    repeated_details_at = _parse_partner_datetime(
                        raw.get('detailCollectedAt') or raw.get('conditionsCollectedAt'),
                        'detailCollectedAt',
                    )
                    if repeated_details_at is not None:
                        snapshot.details_collected_at = max(
                            _as_utc(snapshot.details_collected_at)
                            if snapshot.details_collected_at else repeated_details_at,
                            repeated_details_at,
                        )
                    counters['reused_snapshots'] += 1
                if snapshot.details_status == 'complete':
                    details_count += 1
                offer.current_snapshot_id = snapshot.id

            if completeness == 'complete':
                missing_query = PartnerOffer.query.filter_by(
                    bank_id=bank.id,
                    card_user_id=card_user_id,
                    is_available=True,
                )
                if seen_offer_ids:
                    missing_query = missing_query.filter(
                        ~PartnerOffer.id.in_(seen_offer_ids)
                    )
                for missing in missing_query:
                    missing.is_available = False
                    missing.unavailable_at = collected_at

            errors = summary.get('errors') if isinstance(summary.get('errors'), list) else []
            run = PartnerOfferImportRun(
                bank_id=bank.id,
                card_user_id=card_user_id,
                imported_by_id=g.auth_user.id,
                collected_at=collected_at,
                imported_at=_utc_now(),
                preview_count=len(offers),
                details_count=details_count,
                completeness=completeness,
                errors_json=_canonical_json(errors),
                collector_version=payload.get('collector_version'),
                source_hash=_sha256_json(bank_result),
            )
            db.session.add(run)
            db.session.flush()
            runs.append({
                'id': run.id,
                'bank_id': source_bank_id,
                'completeness': completeness,
                'offers': len(seen_offer_ids),
            })

        db.session.commit()
    except ValueError as error:
        db.session.rollback()
        return jsonify({'error': str(error)}), 400
    except Exception:
        db.session.rollback()
        raise

    return jsonify({**counters, 'runs': runs, 'skipped': skipped})


@app.get('/api/partner-offers')
def list_partner_offers():
    rating = request.args.get('rating')
    if rating not in (None, 'all', *PARTNER_RATINGS):
        return jsonify({'error': 'Invalid rating'}), 400
    try:
        limit = min(max(int(request.args.get('limit', 50)), 1), 100)
        offset = max(int(request.args.get('offset', 0)), 0)
    except ValueError:
        return jsonify({'error': 'limit and offset must be integers'}), 400

    query = (
        db.session.query(PartnerOffer, PartnerOfferSnapshot)
        .join(PartnerOfferSnapshot, PartnerOffer.current_snapshot_id == PartnerOfferSnapshot.id)
        .outerjoin(
            PartnerOfferPreference,
            (PartnerOfferPreference.offer_id == PartnerOffer.id)
            & (PartnerOfferPreference.auth_user_id == g.auth_user.id),
        )
    )
    if request.args.get('include_unavailable') != 'true':
        query = query.filter(PartnerOffer.is_available == True)
    if request.args.get('bank_id'):
        query = query.filter(PartnerOffer.bank_id == request.args['bank_id'])
    if request.args.get('card_user_id'):
        query = query.filter(PartnerOffer.card_user_id == request.args['card_user_id'])
    if rating == 'hidden':
        query = query.filter(PartnerOfferPreference.rating == 'hidden')
    elif rating in ('interesting', 'undecided'):
        if rating == 'undecided':
            query = query.filter(or_(
                PartnerOfferPreference.rating == 'undecided',
                PartnerOfferPreference.id.is_(None),
            ))
        else:
            query = query.filter(PartnerOfferPreference.rating == rating)
    elif rating != 'all':
        query = query.filter(or_(
            PartnerOfferPreference.rating != 'hidden',
            PartnerOfferPreference.id.is_(None),
        ))

    query = query.order_by(
        db.case((PartnerOfferPreference.rating == 'interesting', 0), else_=1),
        PartnerOffer.last_seen_at.desc(),
        PartnerOffer.id,
    )
    total = query.count()
    rows = query.offset(offset).limit(limit).all()
    return jsonify({
        'items': [
            _partner_offer_to_dict(offer, snapshot, g.auth_user.id)
            for offer, snapshot in rows
        ],
        'total': total,
        'limit': limit,
        'offset': offset,
    })


@app.get('/api/partner-offers/<int:offer_id>')
def get_partner_offer(offer_id):
    offer = db.session.get(PartnerOffer, offer_id)
    if offer is None or offer.current_snapshot_id is None:
        return jsonify({'error': 'Partner offer not found'}), 404
    snapshot = db.session.get(PartnerOfferSnapshot, offer.current_snapshot_id)
    if snapshot is None:
        return jsonify({'error': 'Partner offer snapshot not found'}), 404
    return jsonify(_partner_offer_to_dict(
        offer,
        snapshot,
        g.auth_user.id,
        include_details=True,
    ))


@app.get('/api/partner-offers/<int:offer_id>/icon')
def partner_offer_icon(offer_id):
    offer = db.session.get(PartnerOffer, offer_id)
    if offer is None or offer.current_snapshot_id is None:
        return jsonify({'error': 'Partner offer icon not found'}), 404
    snapshot = db.session.get(PartnerOfferSnapshot, offer.current_snapshot_id)
    if snapshot is None or not snapshot.icon_url:
        return jsonify({'error': 'Partner offer icon not found'}), 404
    try:
        content, mime_type = _fetch_partner_icon(snapshot.icon_url)
    except Exception:
        app.logger.warning(
            'Unable to load partner offer icon for offer %s',
            offer_id,
            exc_info=True,
        )
        return jsonify({'error': 'Partner offer icon is unavailable'}), 502
    return Response(
        content,
        mimetype=mime_type,
        headers={'Cache-Control': 'public, max-age=86400, stale-if-error=604800'},
    )


@app.put('/api/partner-offers/<int:offer_id>/preference')
def update_partner_offer_preference(offer_id):
    offer = db.session.get(PartnerOffer, offer_id)
    if offer is None:
        return jsonify({'error': 'Partner offer not found'}), 404
    payload = request.get_json(silent=True) or {}
    rating = payload.get('rating')
    if rating not in PARTNER_RATINGS:
        return jsonify({'error': 'Invalid rating'}), 400

    now = _utc_now()
    preference = _partner_preference(offer.id, g.auth_user.id)
    if preference is None:
        preference = PartnerOfferPreference(
            auth_user_id=g.auth_user.id,
            offer_id=offer.id,
            rating=rating,
            created_at=now,
            updated_at=now,
        )
        db.session.add(preference)
    else:
        preference.rating = rating
        preference.updated_at = now
    db.session.commit()
    return jsonify({
        'offer_id': offer.id,
        'rating': preference.rating,
        'updated_at': _as_utc(preference.updated_at).isoformat(),
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
