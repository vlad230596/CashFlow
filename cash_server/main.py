from flask import Flask, jsonify, request
from flask_cors import CORS  # Импортируем CORS
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

from sqlalchemy import select

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///cards.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

CORS(app)


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

    def to_dict(self):
        return {
            'id': self.id,
            'payment_system': self.payment_system,
            'card_type': self.card_type,
            'last_four_digits': self.last_four_digits,
            'bank_id': self.bank_id,
            'user_id': self.user_id,
            'created_at': self.created_at.isoformat(),
            'is_active': self.is_active
        }


# Модель для категорий кешбека
class CashbackCategory(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(50), nullable=False)
    start_date = db.Column(db.DateTime, nullable=False)
    end_date = db.Column(db.DateTime, nullable=False)
    is_selected = db.Column(db.Boolean, default=False)
    cashback_percent = db.Column(db.Float, nullable=False)

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
            'card_id': self.card_id
        }


# Создаём таблицы при запуске приложения
with app.app_context():
    # db.drop_all()
    db.create_all()


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
            is_active=data.get('is_active', True)
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
            is_selected=data.get('is_selected', False)
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


@app.route('/api/active_cashback', methods=['GET'])
def get_active_cashback():
    today = datetime.now().date()

    # Получаем все активные карты
    active_cards = BankCard.query.filter_by(is_active=True).all()

    result = []

    for card in active_cards:
        # Получаем активные категории для карты
        active_categories = CashbackCategory.query.filter(
            CashbackCategory.card_id == card.id,
            CashbackCategory.is_selected == True,
            CashbackCategory.start_date <= today,
            CashbackCategory.end_date >= today
        ).all()

        if active_categories:
            card_data = {
                "name": f"{card.bank.name} {card.user.name}",
                "number": card.last_four_digits,
                "categories": [
                    {
                        "name": category.name,
                        "percent": category.cashback_percent
                    } for category in active_categories
                ]
            }
            result.append(card_data)

    return jsonify(result)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)