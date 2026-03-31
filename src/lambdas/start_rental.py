import boto3
import json
import os

stepfunctions = boto3.client('stepfunctions')
STATE_MACHINE_ARN = os.environ.get('STATE_MACHINE_ARN')

def lambda_handler(event, context):
    try:
        # Para integración AWS_PROXY, el body viene como string en event['body']
        body = json.loads(event['body']) if event.get('body') else {}
        movie_id = body.get('movie_id')
        user_id = body.get('user_id')
        
        if not movie_id or not user_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'movie_id and user_id are required'})
            }
        
        response = stepfunctions.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            input=json.dumps({'movie_id': movie_id, 'user_id': user_id})
        )
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'execution_arn': response['executionArn'],
                'status': 'RUNNING'
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }