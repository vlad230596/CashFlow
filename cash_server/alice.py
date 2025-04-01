from flask import Flask, request, jsonify
from flask_cors import CORS
import ssl
import random

app = Flask(__name__)
CORS(app)




def parse_and_generate_response(user_text):
    # Определяем категорию (аптека, кафе, транспорт и т.д.)
    category = "другое"
    if "аптек" in user_text.lower():
        category = "аптека"
    elif "кафе" in user_text.lower() or "ресторан" in user_text.lower():
        category = "кафе"
    elif "транспорт" in user_text.lower() or "метро" in user_text.lower():
        category = "транспорт"
    elif "озон" in user_text.lower():
        category = "озон"

    if category == "озон":
        return "В Озоне хватит покупать, я думаю."

    # Параметры для генерации ответа
    names = ["Влад", "Катя"]
    banks = ["ОТП", "Сбер", "Альфа"]
    cashbacks = {
        "аптека": random.randint(2, 5),
        "кафе": random.randint(3, 7),
        "транспорт": random.randint(1, 4),
        "другое": random.randint(1, 3)
    }

    # Выбираем случайные значения
    name = random.choice(names)
    bank = random.choice(banks)
    percent = cashbacks[category]

    # Формируем ответ
    responses = [
        f"Плати картой {bank} {name}, там {percent}% кэшбэка",
        f"Лучше использовать карту {bank} {name} - {percent}% вернётся",
        f"Для этого подходит карта {bank} {name} ({percent}% кэшбэка)"
    ]
    response = random.choice(responses)
    return response

@app.route('/webhook', methods=['POST'])
def webhook():
    try:
        data = request.json  # Проверяем JSON
        if not data:
            return jsonify({"error": "Invalid JSON"}), 400
        print(data['request'])
        user_text = data.get('request', {}).get('command', '')
        response = {
            "version": "1.0",
            "response": {
                "text": f"{parse_and_generate_response(user_text)}",
                "end_session": True
            }
        }
        return jsonify(response)

    except Exception as e:
        return jsonify({"error": str(e)}), 400


if __name__ == '__main__':
    context = ssl.SSLContext(ssl.PROTOCOL_TLSv1_2)
    context.load_cert_chain('ssl/localhost.pem', 'ssl/localhost-key.pem')
    app.run(port=5000, ssl_context=context)  # CloudPub будет перенаправлять HTTPS сюда