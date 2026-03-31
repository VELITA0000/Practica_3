#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_MACHINE_FILE="$PROJECT_ROOT/infrastructure/state_machine.json"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/LabRole"

sed "s/\${ACCOUNT_ID}/$ACCOUNT_ID/g" "$STATE_MACHINE_FILE" > /tmp/state_machine_processed.json

aws stepfunctions create-state-machine \
    --name "FilmRentalsStateMachine" \
    --definition file:///tmp/state_machine_processed.json \
    --role-arn "$ROLE_ARN" \
    --region us-east-1 \
    2>/dev/null || aws stepfunctions update-state-machine \
        --state-machine-arn "arn:aws:states:us-east-1:$ACCOUNT_ID:stateMachine:FilmRentalsStateMachine" \
        --definition file:///tmp/state_machine_processed.json \
        --role-arn "$ROLE_ARN" \
        --region us-east-1

echo "Step Function desplegada."