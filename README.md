# Practica 3

## Descripcion

En la práctica se implementa una plataforma de renta de peliculas utilizando servicios serverless de AWS. El sistema permite buscar peliculas, rentar una, consultar el estado de rentas de un usuario y recibir alertas por correo cuando una renta está próxima a vencer. La arquitectura está compuesta por Amazon RDS (PostgreSQL) para el almacenamiento persistente, AWS Lambda para la lógica de negocio, AWS Step Functions para la orquestación de rentas, Amazon API Gateway para exponer endpoints HTTP, Amazon SNS para notificaciones y Amazon EventBridge para la ejecución programada de alertas. Todo el despliegue se automatiza mediante scripts en Bash, para poder reproducir de forma más simplificada la infraestructura.


### Reglas de Negocio Implementadas

- Una película se renta por máximo 1 semana y no es posible extender el plazo.
- Un usuario no puede tener más de 2 rentas activas al mismo tiempo.
- A partir de 3 días antes del vencimiento, el sistema notifica al usuario
  diariamente con cuántos días le quedan.


### Componentes

**Base de Datos (Amazon RDS PostgreSQL):**
Las credenciales de conexión se guardan en Secrets Manager para que las Lambdas las obtengan de forma segura.
- Tabla movies: Almacena el catálogo de películas con movieId, title y genres. Se carga inicialmente desde el dataset MovieLens.
  
- Tabla users: Contiene los usuarios del sistema con user_id, name y email. Los emails se usan para suscripciones SNS.
  
- Tabla rentals: Registra cada renta con movie_id, user_id, rented_at, expires_at (7 días después) y returned_at (NULL si activa).

**Funciones Lambda**
Cada Lambda tiene una responsabilidad única. Todas las Lambdas, excepto start_rental y check_expirations, acceden a RDS mediante credenciales de Secrets Manager.
- search_movies: 
    Busca películas por título y determina si están rentadas.
    Obtiene credenciales seguras, conecta a RDS, ejecuta la consulta que incluye la subconsulta para detectar rentas activas, y devuelve los resultados formateados.

- start_rental: 
    Recibe la solicitud de renta e inicia la Step Function.
    Lee el ARN de la Step Function desde variable de entorno (inyectada por el script create_lambdas.sh), inicia la ejecución y devuelve el ARN de la ejecución.

- check_rental_status: 
    Devuelve todas las rentas activas de un usuario.

- check_movie_exists: 
    Verifica que el movie_id exista en la tabla movies.

- check_movie_available: 
    Comprueba que la película no tenga una renta activa.

- check_user_limit: 
    Cuenta las rentas activas del usuario y asegura que sean ≤2.

- create_rental: 
    Inserta la renta en la tabla rentals con fechas.

- check_expirations: 
    Consulta rentas próximas a vencer y publica en SNS.
    Obtiene el ARN del tema SNS desde variable de entorno, consulta las rentas próximas a vencer y publica un mensaje para cada una, incluyendo el user_id como atributo para que SNS aplique el filtro.

**Step Functions**
La máquina de estados RentalStateMachine orquesta los pasos de validación y creación de renta. Cada paso es una tarea Lambda. En caso de error, se dirige a un estado Fail. Obtiene el ARN del tema SNS desde variable de entorno, consulta las rentas próximas a vencer y publica un mensaje para cada una, incluyendo el user_id como atributo para que SNS aplique el filtro.

**API Gateway**
Se crea una API HTTP con tres rutas:
- GET /movies?name={name} → integra con search_movies
- POST /rent → integra con start_rental
- GET /status/{user_id} → integra con check_rental_status

**SNS (Simple Notification Service)**
El tema rentals-expiring-soon se suscribe a los correos de los usuarios con una política de filtro basada en user_id. Por ejemplo, la suscripción del usuario con user_id=1 tiene filtro {"user_id": ["1"]}. Cuando la Lambda check_expirations publica un mensaje con el atributo user_id, SNS dirige el mensaje solo a la suscripción correspondiente.
- Relación entre Correo, Usuario y Suscripción
    Cada usuario está representado en la tabla users con un user_id único y un email. Para recibir alertas, se crea una suscripción en SNS que vincula ese email con una política de filtro basada en user_id. De este modo, cuando la Lambda check_expirations publica un mensaje con MessageAttributes.user_id, SNS entrega el mensaje únicamente a las suscripciones cuyo filtro coincida. Esto garantiza que cada usuario reciba solo sus propias notificaciones.

    Si se modifica el email de un usuario en la tabla users, también debe actualizarse la suscripción en SNS (eliminando la antigua y creando una nueva con el nuevo email, manteniendo el mismo filtro user_id). De lo contrario, las alertas seguirán enviándose al correo antiguo. El sistema no sincroniza automáticamente estos cambios, por lo que la gestión debe ser manual o mediante scripts adicionales.

**EventBridge**
Una regla programada (cron(0 9 * * ? *)) dispara la Lambda check_expirations todos los días a las 9:00 UTC.

**Secrets Manager**
Almacena dos secretos:
- filmrentals/rds/host: string con el endpoint de RDS.
- filmrentals/rds/credentials: JSON con username y password

**IAM Roles**
El rol LabRole otorga permisos a las Lambdas para acceder a Secrets Manager, RDS (a través de VPC), SNS y Step Functions. También permite a API Gateway invocar Lambdas y a EventBridge invocar check_expirations.


### Flujo de Trabajo

**Búsqueda de Películas**
1. El cliente realiza GET /movies?name=toy.
2. API Gateway invoca la Lambda search_movies.
3. La Lambda obtiene credenciales de Secrets Manager y se conecta a RDS.
4. Ejecuta consulta que busca coincidencias en title y verifica existencia de rentas activas.
5. Devuelve lista JSON con movie_id, title e is_rented.

**Renta de una Película**
1. El cliente envía POST /rent con {"movie_id":123,"user_id":"1"}.
2. start_rental recibe la solicitud, inicia la Step Function con los datos y devuelve execution_arn.
3. La Step Function ejecuta secuencialmente:
4. check_movie_exists → verifica en RDS.
5. check_movie_available → comprueba que no haya renta activa.
6. check_user_limit → cuenta rentas activas del usuario.
7. create_rental → inserta registro en rentals con fechas.
8. Si alguna validación falla, la Step Function termina en estado Fail y el cliente puede consultar el estado mediante el ARN de ejecución (no implementado en el frontend, pero puede verse en logs).

**Consulta de Rentas Activas**
1. GET /status/1 → API Gateway invoca check_rental_status.
2. La Lambda consulta RDS por rentas con user_id=1 y returned_at IS NULL.
3. Devuelve lista con rental_id, title, rented_at, expires_at.

**Alertas de Vencimiento**
1. Diariamente a las 9:00 UTC, EventBridge dispara la Lambda check_expirations.
2. La Lambda consulta RDS: rentas activas con expires_at <= now() + 3 days.
3. Para cada renta, calcula días restantes, construye mensaje y publica en el tema SNS con MessageAttributes.user_id.
4. SNS filtra el mensaje a la(s) suscripción(es) cuyo filtro coincida con el user_id.
5. Cada usuario recibe un correo con el aviso correspondiente.


## Configuracion

### Requisitos

- Cuenta de AWS con permisos para crear recursos
- AWS CLI instalado y configurado con credenciales
- `psql` instalado (para conectarse a RDS).
- `jq` instalado (para procesar JSON).
- Python 3.9+ y pip.


### Despliegue

**Abrir bash**  
```Ubuntu```

**Ir a raiz de consola**     
```cd ~```

**Eliminar anterior version**    
```rm -r practica_3.2```

**Copiar proyecto a raiz de bash**   
```cp -r "/mnt/unidad/ruta/proyecto" .```

**Ver si se copio el proyecto**  
```ls```

**Entrar a raiz de proyecto**    
```cd proyecto```

**Dar permisos de ejecucion**    
```chmod +x infrastructure/scripts/*.sh```

**Ejecutar deploy para correr todos los scripts**  
```./infrastructure/scripts/deploy.sh```

**Aceptar suscripcion de correos establecidos**  
```Ir a correos - click en aceptar suscripcion```

**Volver a ejecutar script para aplicar filtros a correos**    
```./infrastructure/scripts/deploy_sns_eventbridge.sh```


## Pruebas

### Base de datos

**Conectarse a base de datos**   
```HOST=$(aws secretsmanager get-secret-value --secret-id filmrentals/rds/host --query SecretString --output text)```    
```psql -h $HOST -U postgres -d postgres```

**Ver tablas**   
```\dt```

```\d movies```
```\d rentals```
```\d users```

**Ver num de peliculas**     
```SELECT COUNT(*) FROM movies;```

**Ver usuarios**     
```SELECT user_id, name, email FROM users;```

**Ver rentas**   
```SELECT * FROM rentals ORDER BY id;```

**Eliminar rentas**  
```DELETE FROM rentals;```

**Buscar pelicula con "toy"**    
```curl "https://9xruuxvi18.execute-api.us-east-1.amazonaws.com/dev/movies?name=toy"```

**Salir de base de datos**   
```\q```


### Prueba de lambdas

**Rentar pelicula 1**    
```
curl -X POST "https://9xruuxvi18.execute-api.us-east-1.amazonaws.com/dev/rent" \
  -H "Content-Type: application/json" \
  -d '{"movie_id": 1, "user_id": "1"}'
```

**Consultar rentas activas de usuario 1**    
```curl "https://9xruuxvi18.execute-api.us-east-1.amazonaws.com/dev/status/1"```


### Prueba de step functions

**Rentar pelicula 2**    
```
curl -X POST "https://9xruuxvi18.execute-api.us-east-1.amazonaws.com/dev/rent" \
  -H "Content-Type: application/json" \
  -d '{"movie_id": 2, "user_id": "1"}'
```

**Rentar pelicula 3**  
```
curl -X POST "https://9xruuxvi18.execute-api.us-east-1.amazonaws.com/dev/rent" \
  -H "Content-Type: application/json" \
  -d '{"movie_id": 3, "user_id": "1"}'
```

**Rentar pelicula que no existe**    
```
curl -X POST "https://9xruuxvi18.execute-api.us-east-1.amazonaws.com/dev/rent" \
  -H "Content-Type: application/json" \
  -d '{"movie_id": 99999, "user_id": "2"}'
```