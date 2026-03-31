#!/bin/bash
DB_INSTANCE_IDENTIFIER=$1
while true; do
    STATUS=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" --region us-east-1 --query 'DBInstances[0].DBInstanceStatus' --output text)
    echo "Estado de RDS: $STATUS"
    if [ "$STATUS" == "available" ]; then
        break
    fi
    sleep 30
done