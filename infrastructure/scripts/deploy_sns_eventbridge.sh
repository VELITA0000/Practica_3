#!/bin/bash
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TOPIC_NAME="rentals-expiring-soon"
TOPIC_ARN="arn:aws:sns:us-east-1:$ACCOUNT_ID:$TOPIC_NAME"

echo "Configurando SNS topic..."
aws sns create-topic --name "$TOPIC_NAME" --region us-east-1 > /dev/null 2>&1 || echo "Topic ya existe"

# Obtener emails y user_ids desde la tabla users
echo "Obteniendo usuarios de la base de datos..."
HOST=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/host --query SecretString --output text)
USERNAME=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/credentials --query SecretString --output text | jq -r .username)
PASSWORD=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/credentials --query SecretString --output text | jq -r .password)

export PGPASSWORD=$PASSWORD
# Consulta que devuelve user_id y email (separados por tab)
USERS=$(psql -h "$HOST" -U "$USERNAME" -d postgres -t -A -F $'\t' -c "SELECT user_id, email FROM users WHERE email IS NOT NULL AND email != ''" 2>/dev/null || true)
unset PGPASSWORD

if [ -z "$USERS" ]; then
    echo "No se encontraron usuarios con email en la base de datos. Omitiendo suscripciones SNS."
else
    echo "Creando suscripciones SNS para cada usuario (requieren confirmación por email)..."
    while IFS=$'\t' read -r USER_ID EMAIL; do
        if [ -n "$EMAIL" ]; then
            echo "Suscribiendo $EMAIL (user_id: $USER_ID)"
            aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$EMAIL" --region us-east-1 || true
        fi
    done <<< "$USERS"
fi

# Configurar política de filtro para que cada usuario reciba solo sus mensajes
echo "Configurando políticas de filtro..."
# Obtener suscripciones confirmadas (ARN real) junto con el email
SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --region us-east-1 --query 'Subscriptions[?SubscriptionArn!="PendingConfirmation"].{Arn:SubscriptionArn,Endpoint:Endpoint}' --output text)

export PGPASSWORD=$PASSWORD
while read -r SUB_ARN ENDPOINT; do
    if [ -z "$SUB_ARN" ]; then continue; fi
    # Buscar el user_id correspondiente a ese email en la base de datos
    USER_ID=$(psql -h "$HOST" -U "$USERNAME" -d postgres -t -A -c "SELECT user_id FROM users WHERE email = '$ENDPOINT'" 2>/dev/null || true)
    if [ -n "$USER_ID" ]; then
        FILTER_POLICY="{\"user_id\": [\"$USER_ID\"]}"
        echo "Aplicando filtro a $SUB_ARN: user_id = $USER_ID"
        aws sns set-subscription-attributes --subscription-arn "$SUB_ARN" --attribute-name FilterPolicy --attribute-value "$FILTER_POLICY" --region us-east-1 || true
    fi
done <<< "$SUBSCRIPTIONS"
unset PGPASSWORD

# Configurar EventBridge rule
RULE_NAME="daily-rental-alerts"
echo "Configurando regla de EventBridge..."
aws events put-rule \
    --name "$RULE_NAME" \
    --schedule-expression "cron(0 9 * * ? *)" \
    --state ENABLED \
    --region us-east-1 || echo "Regla ya existe"

# Agregar target (Lambda notify_expiring)
LAMBDA_ARN="arn:aws:lambda:us-east-1:$ACCOUNT_ID:function:filmrentals_notify_expiring"
aws events put-targets \
    --rule "$RULE_NAME" \
    --targets "Id"="1","Arn"="$LAMBDA_ARN" \
    --region us-east-1 || echo "Target ya existe"

# Dar permiso a EventBridge para invocar Lambda
aws lambda add-permission \
    --function-name filmrentals_notify_expiring \
    --statement-id "EventBridgeInvoke" \
    --action "lambda:InvokeFunction" \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:us-east-1:$ACCOUNT_ID:rule/$RULE_NAME" \
    --region us-east-1 || true

echo "SNS y EventBridge configurados."