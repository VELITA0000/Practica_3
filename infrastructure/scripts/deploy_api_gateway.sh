#!/bin/bash
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
API_NAME="filmrentals-api"
STAGE="dev"

# Verificar si la API ya existe
API_ID=$(aws apigateway get-rest-apis --region us-east-1 --query "items[?name=='$API_NAME'].id" --output text)

if [ -z "$API_ID" ]; then
    echo "Creando nueva API Gateway: $API_NAME"
    API_ID=$(aws apigateway create-rest-api --name "$API_NAME" --region us-east-1 --query 'id' --output text)
else
    echo "Usando API Gateway existente: $API_ID"
fi

# Guardar API_ID para referencia
echo "$API_ID" > /tmp/api_id.txt
echo "https://$API_ID.execute-api.us-east-1.amazonaws.com/$STAGE" > .api_url

# Obtener ID del recurso raíz
ROOT_ID=$(aws apigateway get-resources --rest-api-id $API_ID --region us-east-1 --query 'items[?path==`/`].id' --output text)

# Función auxiliar para crear recurso y método con integración Lambda (AWS_PROXY)
create_lambda_integration() {
    local parent_id=$1
    local path_part=$2
    local http_method=$3
    local lambda_name=$4

    local resource_id
    resource_id=$(aws apigateway get-resources --rest-api-id $API_ID --region us-east-1 --query "items[?parentId=='$parent_id' && pathPart=='$path_part'].id" --output text)
    if [ -z "$resource_id" ]; then
        resource_id=$(aws apigateway create-resource --rest-api-id $API_ID --region us-east-1 --parent-id $parent_id --path-part $path_part --query 'id' --output text)
    fi

    # Crear método
    aws apigateway put-method --rest-api-id $API_ID --region us-east-1 --resource-id $resource_id --http-method $http_method --authorization-type NONE

    # Integración con Lambda
    local lambda_arn="arn:aws:lambda:us-east-1:$ACCOUNT_ID:function:$lambda_name"
    aws apigateway put-integration \
        --rest-api-id $API_ID \
        --region us-east-1 \
        --resource-id $resource_id \
        --http-method $http_method \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$lambda_arn/invocations"
}

# 1. Recurso /movies (GET)
create_lambda_integration "$ROOT_ID" "movies" "GET" "filmrentals_get_movies"

# 2. Recurso /rent (POST) con Lambda start_rental
create_lambda_integration "$ROOT_ID" "rent" "POST" "filmrentals_start_rental"

# 3. Recurso /status/{user_id} (GET)
STATUS_ID=$(aws apigateway get-resources --rest-api-id $API_ID --region us-east-1 --query "items[?parentId=='$ROOT_ID' && pathPart=='status'].id" --output text)
if [ -z "$STATUS_ID" ]; then
    STATUS_ID=$(aws apigateway create-resource --rest-api-id $API_ID --region us-east-1 --parent-id $ROOT_ID --path-part status --query 'id' --output text)
fi

USER_ID_RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_ID --region us-east-1 --query "items[?parentId=='$STATUS_ID' && pathPart=='{user_id}'].id" --output text)
if [ -z "$USER_ID_RESOURCE_ID" ]; then
    USER_ID_RESOURCE_ID=$(aws apigateway create-resource --rest-api-id $API_ID --region us-east-1 --parent-id $STATUS_ID --path-part '{user_id}' --query 'id' --output text)
fi

# Crear método GET con parámetro de ruta
aws apigateway put-method --rest-api-id $API_ID --region us-east-1 --resource-id $USER_ID_RESOURCE_ID --http-method GET --authorization-type NONE --request-parameters '{"method.request.path.user_id": true}'

# Integración con Lambda get_status
LAMBDA_STATUS_ARN="arn:aws:lambda:us-east-1:$ACCOUNT_ID:function:filmrentals_get_status"
aws apigateway put-integration \
    --rest-api-id $API_ID \
    --region us-east-1 \
    --resource-id $USER_ID_RESOURCE_ID \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$LAMBDA_STATUS_ARN/invocations"

# Desplegar API
aws apigateway create-deployment --rest-api-id $API_ID --stage-name $STAGE --region us-east-1

echo "API Gateway desplegado. URL: https://$API_ID.execute-api.us-east-1.amazonaws.com/$STAGE"