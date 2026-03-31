import json
from utils.db import get_db_connection

def lambda_handler(event, context):
    user_id = event.get('pathParameters', {}).get('user_id')
    if not user_id:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'user_id es requerido'})
        }

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        query = """
            SELECT r.id as rental_id, m.title, r.rented_at, r.expires_at
            FROM rentals r
            JOIN movies m ON r.movie_id = m.movieId
            WHERE r.user_id = %s AND r.returned_at IS NULL
        """
        cur.execute(query, (user_id,))
        rows = cur.fetchall()
        result = []
        for row in rows:
            result.append({
                'rental_id': row[0],
                'title': row[1],
                'rented_at': row[2].isoformat(),
                'expires_at': row[3].isoformat()
            })
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