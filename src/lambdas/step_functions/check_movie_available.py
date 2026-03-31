from utils.db import get_db_connection

def lambda_handler(event, context):
    movie_id = event['movie_id']
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute('SELECT 1 FROM rentals WHERE movie_id = %s AND returned_at IS NULL', (movie_id,))
        active = cur.fetchone()
        if active:
            raise Exception('Movie is already rented')
        return event
    finally:
        cur.close()
        conn.close()