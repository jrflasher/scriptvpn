import telegram
from telegram.ext import Updater, CommandHandler, MessageHandler, Filters
import sqlite3
import os

BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"
DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'database', 'accounts.db')

def start(update, context):
    update.message.reply_text('JR-XRAY Bot\nGunakan /help untuk perintah')

def list_accounts(update, context):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM accounts")
    accounts = cursor.fetchall()
    conn.close()
    
    response = "Daftar Akun:\n"
    for acc in accounts:
        response += f"ID: {acc[0]} | User: {acc[1]}\n"
    
    update.message.reply_text(response)

def main():
    updater = Updater(BOT_TOKEN, use_context=True)
    dp = updater.dispatcher

    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CommandHandler("list", list_accounts))

    updater.start_polling()
    updater.idle()

if __name__ == '__main__':
    main()