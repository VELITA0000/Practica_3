import json
from utils.db import get_db_connection

def lambda_handler(event, context):
    name = event.get('queryStringParameters', {}).get('name', '')
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        query = """
            SELECT m.movieId as movie_id, m.title,
                   CASE WHEN r.id IS NOT NULL THEN true ELSE false END as is_rented
            FROM movies m
            LEFT JOIN rentals r ON m.movieId = r.movie_id AND r.returned_at IS NULL
            WHERE m.title ILIKE %s
            LIMIT 50
        """
        cur.execute(query, (f'%{name}%',))
        rows = cur.fetchall()
        result = [{'movie_id': row[0], 'title': row[1], 'is_rented': row[2]} for row in rows]
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps(result)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
    finally:
        cur.close()
        conn.close()