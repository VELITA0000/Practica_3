from utils.db import get_db_connection

def lambda_handler(event, context):
    movie_id = event['movie_id']
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute('SELECT 1 FROM movies WHERE movieId = %s', (movie_id,))
        exists = cur.fetchone()
        if not exists:
            raise Exception('Movie does not exist')
        return event
    finally:
        cur.close()
        conn.close()