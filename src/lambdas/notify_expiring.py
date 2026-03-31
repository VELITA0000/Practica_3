import boto3
import json
import os
from datetime import datetime, timedelta
from utils.db import get_db_connection

sns_client = boto3.client('sns')
TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', 'arn:aws:sns:us-east-1:123456789012:rentals-expiring-soon')

def lambda_handler(event, context):
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        # Rentas activas con expiración en los próximos 3 días
        query = """
            SELECT r.user_id, m.title, r.expires_at
            FROM rentals r
            JOIN movies m ON r.movie_id = m.movieId
            WHERE r.returned_at IS NULL
              AND r.expires_at BETWEEN NOW() AND NOW() + INTERVAL '3 days'
        """
        cur.execute(query)
        rows = cur.fetchall()

        for row in rows:
            user_id = row[0]
            title = row[1]
            expires_at = row[2]
            days_left = (expires_at - datetime.utcnow()).days
            if days_left < 0:
                days_left = 0

            message = f"Tu renta de la película '{title}' vence en {days_left} días."

            # Publicar con atributo de filtro para user_id
            sns_client.publish(
                TopicArn=TOPIC_ARN,
                Message=message,
                MessageAttributes={
                    'user_id': {
                        'DataType': 'String',
                        'StringValue': str(user_id)
                    }
                }
            )

        return {
            'statusCode': 200,
            'body': json.dumps({'notified': len(rows)})
        }
    except Exception as e:
        print(f"Error: {e}")
        raise
    finally:
        cur.close()
        conn.close()