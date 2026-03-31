#!/bin/bash
set -e

# Obtener credenciales de RDS desde Secrets Manager
HOST=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/host --query SecretString --output text)
USERNAME=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/credentials --query SecretString --output text | jq -r .username)
PASSWORD=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/credentials --query SecretString --output text | jq -r .password)

export PGPASSWORD=$PASSWORD

# Crear tablas rentals y users
psql -h "$HOST" -U "$USERNAME" -d postgres <<EOF
CREATE TABLE IF NOT EXISTS rentals (
    id          SERIAL PRIMARY KEY,
    movie_id    INTEGER NOT NULL REFERENCES movies(movieId),
    user_id     VARCHAR(50) NOT NULL,
    rented_at   TIMESTAMP NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMP NOT NULL DEFAULT NOW() + INTERVAL '7 days',
    returned_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS users (
    id      SERIAL PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL UNIQUE,
    name    VARCHAR(100) NOT NULL,
    email   VARCHAR(100) NOT NULL
);
EOF

unset PGPASSWORD
echo "Tablas creadas (o ya existían)."