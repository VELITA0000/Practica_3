#!/bin/bash
set -e

# Descargar el archivo ZIP de MovieLens
echo "Descargando dataset de películas..."
curl -s -o /tmp/ml-latest-small.zip "https://files.grouplens.org/datasets/movielens/ml-latest-small.zip"

# Extraer el archivo movies.csv del ZIP
unzip -p /tmp/ml-latest-small.zip ml-latest-small/movies.csv > /tmp/movies.csv

# Obtener credenciales de RDS desde Secrets Manager
HOST=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/host --query SecretString --output text)
USERNAME=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/credentials --query SecretString --output text | jq -r .username)
PASSWORD=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/credentials --query SecretString --output text | jq -r .password)

export PGPASSWORD=$PASSWORD

# Crear tabla movies si no existe
psql -h "$HOST" -U "$USERNAME" -d postgres <<EOF
CREATE TABLE IF NOT EXISTS movies (
    movieId INTEGER PRIMARY KEY,
    title TEXT,
    genres TEXT
);
EOF

# Cargar datos desde el CSV (ignorar encabezado)
psql -h "$HOST" -U "$USERNAME" -d postgres -c "\COPY movies(movieId, title, genres) FROM '/tmp/movies.csv' DELIMITER ',' CSV HEADER;"

unset PGPASSWORD
echo "Datos de películas cargados."