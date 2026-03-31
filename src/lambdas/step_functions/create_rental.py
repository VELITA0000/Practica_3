from utils.db import get_db_connection

def lambda_handler(event, context):
    movie_id = event['movie_id']
    user_id = event['user_id']
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO rentals (movie_id, user_id) VALUES (%s, %s) RETURNING id",
            (movie_id, user_id)
        )
        rental_id = cur.fetchone()[0]
        conn.commit()
        return {
            'status': 'SUCCESS',
            'rental_id': rental_id
        }
    finally:
        cur.close()
        conn.close()