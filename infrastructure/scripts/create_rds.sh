#!/bin/bash
set -e

DB_INSTANCE_IDENTIFIER="filmrentals-db"
DB_NAME="postgres"
MASTER_USERNAME="postgres"
MASTER_PASSWORD="Password123"   # Contraseña fija

echo "Creando instancia RDS $DB_INSTANCE_IDENTIFIER..."

# Verificar si la instancia ya existe
EXISTING=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" --region us-east-1 --query 'DBInstances[0].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
if [ -n "$EXISTING" ]; then
    echo "La instancia RDS ya existe. Usando la existente."
    HOST=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" --region us-east-1 --query 'DBInstances[0].Endpoint.Address' --output text)
else
    # Obtener VPC por defecto y sus subredes
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
    SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text)

    # Crear DB subnet group (si no existe)
    aws rds create-db-subnet-group \
        --db-subnet-group-name filmrentals-subnet-group \
        --db-subnet-group-description "Subnet group for filmrentals" \
        --subnet-ids $SUBNETS \
        --region us-east-1 2>/dev/null || echo "DB subnet group ya existe"

    # Obtener grupo de seguridad por defecto (el primero en la VPC)
    SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)

    # Obtener la última versión disponible de PostgreSQL 14.x
    echo "Obteniendo la última versión de PostgreSQL 14.x disponible..."
    ENGINE_VERSION=$(aws rds describe-db-engine-versions \
        --engine postgres \
        --engine-version 14 \
        --region us-east-1 \
        --query "DBEngineVersions[-1].EngineVersion" \
        --output text)

    if [ -z "$ENGINE_VERSION" ]; then
        echo "No se encontró ninguna versión de PostgreSQL 14. Usando 14.0 como fallback."
        ENGINE_VERSION="14.0"
    fi
    echo "Usando versión: $ENGINE_VERSION"

    # Crear la instancia RDS
    aws rds create-db-instance \
        --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
        --db-instance-class db.t3.micro \
        --engine postgres \
        --engine-version "$ENGINE_VERSION" \
        --master-username "$MASTER_USERNAME" \
        --master-user-password "$MASTER_PASSWORD" \
        --allocated-storage 20 \
        --storage-type gp2 \
        --publicly-accessible \
        --db-subnet-group-name filmrentals-subnet-group \
        --vpc-security-group-ids "$SECURITY_GROUP_ID" \
        --backup-retention-period 0 \
        --no-multi-az \
        --region us-east-1

    echo "Esperando a que RDS esté disponible (esto puede tomar varios minutos)..."
    bash infrastructure/scripts/wait_for_rds.sh "$DB_INSTANCE_IDENTIFIER"

    HOST=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" --region us-east-1 --query 'DBInstances[0].Endpoint.Address' --output text)
fi

# Guardar secretos en Secrets Manager
echo "Guardando secretos en Secrets Manager..."
aws secretsmanager create-secret \
    --name filmrentals/rds/host \
    --secret-string "$HOST" \
    --region us-east-1 \
    2>/dev/null || aws secretsmanager update-secret \
        --secret-id filmrentals/rds/host \
        --secret-string "$HOST" \
        --region us-east-1

CREDS_JSON=$(printf '{"username":"%s","password":"%s"}' "$MASTER_USERNAME" "$MASTER_PASSWORD")
aws secretsmanager create-secret \
    --name filmrentals/rds/credentials \
    --secret-string "$CREDS_JSON" \
    --region us-east-1 \
    2>/dev/null || aws secretsmanager update-secret \
        --secret-id filmrentals/rds/credentials \
        --secret-string "$CREDS_JSON" \
        --region us-east-1

echo "RDS creada/actualizada. Host: $HOST"