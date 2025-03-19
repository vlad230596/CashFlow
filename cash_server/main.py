from flask import Flask, jsonify
from flask_cors import CORS  # Импортируем CORS
app = Flask(__name__)
CORS(app)
# Пример данных
cards_data = [
    {
        "name": "Карта 1",
        "number": "1234",
        "categories": [
            {"name": "Кино", "percent": 5, "icon": "movie"},
            {"name": "Кафе", "percent": 7, "icon": "local_cafe"},
        ],
    },
    {
        "name": "Карта 2",
        "number": "5678",
        "categories": [
            {"name": "Фастфуд", "percent": 4, "icon": "fastfood"},
            {"name": "Супермаркеты", "percent": 3, "icon": "shopping_cart"},
        ],
    },
]

@app.route('/api/cards', methods=['GET'])
def get_cards():
    return jsonify(cards_data)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)