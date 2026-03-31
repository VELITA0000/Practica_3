#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$PROJECT_ROOT/src"
OUTPUT_DIR="$PROJECT_ROOT/.lambda_packages"

mkdir -p "$OUTPUT_DIR"

# Instalar dependencias para Python 3.9 en arquitectura x86_64
pip install \
    --platform manylinux2014_x86_64 \
    --target /tmp/lambda_deps \
    --python-version 3.9 \
    --only-binary :all: \
    -r "$SRC_DIR/requirements.txt"

# Lista de Lambdas (nombres de archivo sin extensión)
LAMBDAS=(
    "get_movies"
    "get_status"
    "notify_expiring"
    "start_rental"
    "step_functions/check_movie_exists"
    "step_functions/check_movie_available"
    "step_functions/check_user_limit"
    "step_functions/create_rental"
)

for lambda in "${LAMBDAS[@]}"; do
    lambda_name=$(basename "$lambda")
    echo "Empaquetando $lambda_name..."
    WORK_DIR="/tmp/lambda_$lambda_name"
    mkdir -p "$WORK_DIR"
    # Copiar dependencias
    cp -r /tmp/lambda_deps/* "$WORK_DIR/"
    # Copiar código fuente
    cp "$SRC_DIR/lambdas/${lambda}.py" "$WORK_DIR/lambda_function.py"
    # Copiar utils
    mkdir -p "$WORK_DIR/utils"
    cp "$SRC_DIR/utils/db.py" "$WORK_DIR/utils/"
    cp "$SRC_DIR/utils/__init__.py" "$WORK_DIR/utils/" 2>/dev/null || true
    # Crear zip
    cd "$WORK_DIR"
    zip -r "$OUTPUT_DIR/${lambda_name}.zip" .
    cd - > /dev/null
    rm -rf "$WORK_DIR"
done

rm -rf /tmp/lambda_deps
echo "Paquetes generados en $OUTPUT_DIR"