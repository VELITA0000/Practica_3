from utils.db import get_db_connection

def lambda_handler(event, context):
    user_id = event['user_id']
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute('SELECT COUNT(*) FROM rentals WHERE user_id = %s AND returned_at IS NULL', (user_id,))
        count = cur.fetchone()[0]
        if count >= 2:
            raise Exception('User has reached rental limit')
        return event
    finally:
        cur.close()
        conn.close()