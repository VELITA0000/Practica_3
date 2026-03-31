#!/bin/bash
set -e

echo "=== Nuke: Eliminando todos los recursos de FilmRentals ==="
read -p "¿Estás seguro? Escribe 'YES' para continuar: " confirm
if [ "$confirm" != "YES" ]; then
    echo "Cancelado."
    exit 0
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Eliminar Lambdas
echo "Eliminando Lambdas..."
for func in filmrentals_get_movies filmrentals_get_status filmrentals_notify_expiring \
            filmrentals_check_movie_exists filmrentals_check_movie_available \
            filmrentals_check_user_limit filmrentals_create_rental; do
    aws lambda delete-function --function-name "$func" --region us-east-1 || true
done

# Eliminar Step Function
SFN_ARN=$(aws stepfunctions list-state-machines --region us-east-1 --query "stateMachines[?name=='FilmRentalsStateMachine'].stateMachineArn" --output text)
if [ -n "$SFN_ARN" ]; then
    aws stepfunctions delete-state-machine --state-machine-arn "$SFN_ARN" --region us-east-1
    echo "Step Function eliminada."
fi

# Eliminar API Gateway
API_ID=$(aws apigateway get-rest-apis --region us-east-1 --query "items[?name=='filmrentals-api'].id" --output text)
if [ -n "$API_ID" ]; then
    aws apigateway delete-rest-api --rest-api-id "$API_ID" --region us-east-1
    echo "API Gateway eliminado."
fi

# Eliminar SNS topic
TOPIC_ARN=$(aws sns list-topics --region us-east-1 --query "Topics[?contains(TopicArn, 'rentals-expiring-soon')].TopicArn" --output text)
if [ -n "$TOPIC_ARN" ]; then
    aws sns delete-topic --topic-arn "$TOPIC_ARN" --region us-east-1
    echo "Topic SNS eliminado."
fi

# Eliminar regla de EventBridge
RULE_NAME="daily-rental-alerts"
aws events remove-targets --rule "$RULE_NAME" --ids "1" --region us-east-1 || true
aws events delete-rule --name "$RULE_NAME" --region us-east-1 || true

# Eliminar RDS (esperar a que termine la eliminación)
DB_INSTANCE_IDENTIFIER="filmrentals-db"
echo "Eliminando instancia RDS $DB_INSTANCE_IDENTIFIER..."
aws rds delete-db-instance \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
    --skip-final-snapshot \
    --region us-east-1 || echo "La instancia RDS no existe o ya fue eliminada."

# Esperar a que la instancia desaparezca antes de eliminar el subnet group
echo "Esperando a que la instancia RDS termine de eliminarse..."
while true; do
    STATUS=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" --region us-east-1 --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "deleted")
    if [ "$STATUS" == "deleted" ] || [ -z "$STATUS" ]; then
        break
    fi
    echo "Estado actual: $STATUS. Esperando..."
    sleep 30
done

# Eliminar DB subnet group
echo "Eliminando DB subnet group..."
aws rds delete-db-subnet-group --db-subnet-group-name filmrentals-subnet-group --region us-east-1 || echo "Subnet group no existe o ya fue eliminado."

# Eliminar secretos
echo "Eliminando secretos..."
aws secretsmanager delete-secret --secret-id filmrentals/rds/host --force-delete-without-recovery || true
aws secretsmanager delete-secret --secret-id filmrentals/rds/credentials --force-delete-without-recovery || true

echo "=== Todos los recursos han sido eliminados. ==="