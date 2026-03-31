#!/bin/bash
set -e

# Obtener credenciales de RDS desde Secrets Manager
HOST=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/host --query SecretString --output text)
USERNAME=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/credentials --query SecretString --output text | jq -r .username)
PASSWORD=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/credentials --query SecretString --output text | jq -r .password)

export PGPASSWORD=$PASSWORD

# Inserta usuarios con tus correos reales
psql -h "$HOST" -U "$USERNAME" -d postgres <<EOF
INSERT INTO users (user_id, name, email) VALUES
    ('1', 'Usuario Uno', 'dvela020@gmail.com'),
    ('2', 'Usuario Dos', 'davidvelacontreras@gmail.com'),
    ('3', 'Usuario Tres', 'usuario3@example.com')
ON CONFLICT (user_id) DO NOTHING;
EOF

unset PGPASSWORD
echo "Usuarios insertados (o ya existían)."