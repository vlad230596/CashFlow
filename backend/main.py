import base64
import hashlib
import hmac
import os
import re
import secrets
from datetime import datetime, timedelta, timezone

import click
from flask import Flask, g, jsonify, request
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import select, text
from werkzeug.middleware.proxy_fix import ProxyFix

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get(
    'CASHFLOW_DATABASE_URL',
    'sqlite:///cards.db',
)
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['CASHFLOW_ENVIRONMENT'] = os.environ.get('CASHFLOW_ENVIRONMENT', 'development')
app.config['CASHFLOW_SESSION_TTL_HOURS'] = min(
    max(int(os.environ.get('CASHFLOW_SESSION_TTL_HOURS', '12')), 1),
    24,
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
            'max_cashback_amount': self.max_cashback_amount,
            'min_purchase_amount': self.min_purchase_amount,
            'card_id': self.card_id
        }


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


ROLE_LEVELS = {'viewer': 10, 'editor': 20, 'admin': 30}
PUBLIC_ENDPOINTS = {'health', 'ready', 'version', 'login'}
AUTH_TOKEN_BYTES = 32
LOGIN_WINDOW = timedelta(minutes=15)
LOGIN_MAX_FAILURES = 5
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
    if request.path.startswith('/api/auth/users'):
        return 'admin'
    if request.path in ('/api/auth/me', '/api/auth/logout'):
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
    return None


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

    max_selectable = selection.get('maxSelectable')
    selected_count = selection.get('selectedCount')
    if (
        isinstance(max_selectable, int)
        and max_selectable > 0
        and isinstance(selected_count, int)
        and selected_count >= max_selectable
    ):
        return True

    return bool(categories) and all(
        bool(category.get('selected', False)) for category in categories
    )


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
            for imported in categories:
                name = str(imported.get('name') or '').strip()
                percent = imported.get('percent')
                if not name or not isinstance(percent, (int, float)):
                    continue

                category_type = imported.get('type') or 'standard'
                if category_type not in ('standard', 'stackable_bonus'):
                    category_type = 'standard'
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
                category.is_selected = bool(imported.get('selected', False))
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

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
