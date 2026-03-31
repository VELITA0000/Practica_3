#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ZIP_DIR="$PROJECT_ROOT/.lambda_packages"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/LabRole"
STATE_MACHINE_ARN="arn:aws:states:us-east-1:$ACCOUNT_ID:stateMachine:FilmRentalsStateMachine"

declare -A FUNCTIONS=(
    ["get_movies"]="filmrentals_get_movies"
    ["get_status"]="filmrentals_get_status"
    ["notify_expiring"]="filmrentals_notify_expiring"
    ["start_rental"]="filmrentals_start_rental"
    ["check_movie_exists"]="filmrentals_check_movie_exists"
    ["check_movie_available"]="filmrentals_check_movie_available"
    ["check_user_limit"]="filmrentals_check_user_limit"
    ["create_rental"]="filmrentals_create_rental"
)

for zip_file in $(ls "$ZIP_DIR"/*.zip); do
    base_name=$(basename "$zip_file" .zip)
    func_name=${FUNCTIONS[$base_name]}
    if [ -z "$func_name" ]; then
        echo "Ignorando $base_name (no en mapeo)"
        continue
    fi
    echo "Desplegando $func_name..."

    # Construir variables de entorno
    if [ "$func_name" == "filmrentals_notify_expiring" ]; then
        ENV_VARS="Variables={SNS_TOPIC_ARN=arn:aws:sns:us-east-1:$ACCOUNT_ID:rentals-expiring-soon}"
    elif [ "$func_name" == "filmrentals_start_rental" ]; then
        ENV_VARS="Variables={STATE_MACHINE_ARN=$STATE_MACHINE_ARN}"
    else
        ENV_VARS=""
    fi

    # Crear o actualizar función
    if [ -z "$ENV_VARS" ]; then
        aws lambda create-function \
            --function-name "$func_name" \
            --runtime python3.9 \
            --role "$ROLE_ARN" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://$zip_file \
            --region us-east-1 \
            --timeout 10 \
            2>/dev/null || aws lambda update-function-code \
                --function-name "$func_name" \
                --zip-file fileb://$zip_file \
                --region us-east-1
    else
        aws lambda create-function \
            --function-name "$func_name" \
            --runtime python3.9 \
            --role "$ROLE_ARN" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://$zip_file \
            --region us-east-1 \
            --timeout 10 \
            --environment "$ENV_VARS" \
            2>/dev/null || (aws lambda update-function-code \
                --function-name "$func_name" \
                --zip-file fileb://$zip_file \
                --region us-east-1 && \
            aws lambda update-function-configuration \
                --function-name "$func_name" \
                --environment "$ENV_VARS" \
                --region us-east-1)
    fi

    # Agregar permiso para API Gateway
    aws lambda add-permission \
        --function-name "$func_name" \
        --statement-id "apigateway-invoke-${func_name}" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:us-east-1:$ACCOUNT_ID:*/*/*" \
        --region us-east-1 \
        2>/dev/null || true
done

echo "Lambdas desplegadas."