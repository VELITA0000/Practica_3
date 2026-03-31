#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}=== Despliegue completo de FilmRentals ===${NC}"

# 1. Crear RDS (si no existe)
echo -e "${GREEN}1. Configurando RDS...${NC}"
bash infrastructure/scripts/create_rds.sh

# 2. Cargar dataset de películas
echo -e "${GREEN}2. Cargando datos de películas...${NC}"
bash infrastructure/scripts/load_movies.sh

# 3. Crear tablas rentals y users
echo -e "${GREEN}3. Creando tablas rentals y users...${NC}"
bash infrastructure/scripts/create_tables.sh

# 4. Insertar usuarios de prueba (editar emails si se desea)
echo -e "${GREEN}4. Insertando usuarios de prueba...${NC}"
bash infrastructure/scripts/insert_fake_users.sh

# 5. Empaquetar Lambdas
echo -e "${GREEN}5. Empaquetando Lambdas...${NC}"
bash infrastructure/scripts/package_lambdas.sh

# 6. Desplegar Lambdas
echo -e "${GREEN}6. Desplegando Lambdas...${NC}"
bash infrastructure/scripts/deploy_lambdas.sh

# 7. Desplegar Step Function
echo -e "${GREEN}7. Desplegando Step Function...${NC}"
bash infrastructure/scripts/deploy_step_function.sh

# 8. Desplegar API Gateway
echo -e "${GREEN}8. Desplegando API Gateway...${NC}"
bash infrastructure/scripts/deploy_api_gateway.sh

# 9. Configurar SNS y EventBridge
echo -e "${GREEN}9. Configurando SNS y EventBridge...${NC}"
bash infrastructure/scripts/deploy_sns_eventbridge.sh

echo -e "${GREEN}=== Despliegue completado ===${NC}"
if [ -f .api_url ]; then
    echo -e "URL de la API: $(cat .api_url)"
fi