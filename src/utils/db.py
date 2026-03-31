import boto3
import json
import psycopg2
from botocore.exceptions import ClientError

def get_db_connection():
    """
    Obtiene las credenciales de Secrets Manager y devuelve una conexión a PostgreSQL.
    La conexión se cierra automáticamente al terminar la ejecución de la Lambda.
    """
    secrets_client = boto3.client('secretsmanager', region_name='us-east-1')

    try:
        # Obtener host
        host_secret = secrets_client.get_secret_value(SecretId='filmrentals/rds/host')
        host = host_secret['SecretString']

        # Obtener credenciales (username, password)
        creds_secret = secrets_client.get_secret_value(SecretId='filmrentals/rds/credentials')
        creds = json.loads(creds_secret['SecretString'])

        conn = psycopg2.connect(
            host=host,
            user=creds['username'],
            password=creds['password'],
            database='postgres',
            port=5432,
            sslmode='require'
        )
        return conn
    except ClientError as e:
        print(f"Error obteniendo secretos: {e}")
        raise
    except psycopg2.Error as e:
        print(f"Error de conexión a la base de datos: {e}")
        raise