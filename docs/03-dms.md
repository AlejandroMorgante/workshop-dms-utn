# 03 · Conectar Aurora y S3 con AWS DMS

Esta etapa termina con una instancia de replicación y dos conexiones probadas.
Dejamos preparada la generación automática de Glue Data Catalog; las tareas y
los primeros datos llegan en la etapa 04. La explicación para clase está en
[la web](https://utn.almorgan.dev/etapa-03-dms.html).

## Las piezas

| Pieza | Función |
| --- | --- |
| Instancia DMS 3.6.1, `dms.t3.small`, 50 GB | Ejecutar las futuras tareas. Privada y de una sola AZ. |
| Source endpoint | Conectarse a Aurora mediante TLS con `verify-full`. |
| Target endpoint | Escribir Parquet en el bucket de la etapa 02. |
| Usuario `dms_reader` y secreto dedicado | Leer las tablas y usar replicación lógica. |
| Roles IAM | Acceder a red, secreto, S3, Glue, Athena y futuros logs de tareas. |
| Gateway endpoint S3 | Dar acceso a S3 desde las subnets privadas. |
| Interface endpoints | Acceder a Secrets Manager, Glue, Athena y CloudWatch Logs. |

Los cuatro endpoints de interfaz usan una sola subnet para simplificar el taller.
No es una arquitectura de alta disponibilidad. La instancia DMS, su almacenamiento,
los endpoints de interfaz, Secrets Manager y la clave KMS generan consumo aunque
no haya una tarea corriendo. No dejes esta etapa levantada entre encuentros sin
revisar ese consumo y la limpieza.

El stack **`infra/03-dms/`** lee los estados locales de `01-aurora` y `02-s3`.
Conservá las carpetas y sus estados en este checkout. No copia recursos ni toma
control de los anteriores. El usuario SQL se prepara con un asistente aparte.

## 1. Actualizar las salidas de las etapas anteriores

Con el código actualizado, revisá y aplicá ambos planes:

```sh
terraform -chdir=infra/01-aurora plan
terraform -chdir=infra/01-aurora apply
terraform -chdir=infra/02-s3 plan
terraform -chdir=infra/02-s3 apply
```

Estos cambios agregan outputs de integración y evitan que Aurora administre
reglas de ingreso inline. La etapa 03 es dueña de la regla que permite acceso
**solo desde el security group DMS, por el puerto 5432**. Reaplicar Aurora no
debe borrar esa regla. Aurora conserva acceso público deshabilitado.

S3 incorpora una regla de lifecycle: elimina versiones no actuales después de un
día, marcadores de borrado vencidos y cargas multipart incompletas tras un día.
No vence los objetos actuales. DMS recomienda limpiar versiones antiguas en
buckets versionados; el procesamiento de lifecycle es asíncrono y no reemplaza
la limpieza al terminar.

Comprobá que la base está cargada con las cuatro tablas de la etapa 01 y que
`rds.logical_replication` está activo. Aurora debe tener `synchronous_commit=on`;
verificalo mediante Data API con `SHOW synchronous_commit` antes de avanzar.

## 2. Confirmar identidad y roles de la cuenta

```sh
aws sts get-caller-identity --profile workshop
aws iam get-role --role-name dms-vpc-role --profile workshop
aws iam get-role --role-name dms-cloudwatch-logs-role --profile workshop
```

`NoSuchEntity` significa que ese rol no existe. Si recibís `AccessDenied`, corregí
el permiso de lectura antes de decidir si crearlo.

Copiá `infra/03-dms/terraform.tfvars.example` como `infra/03-dms/terraform.tfvars`.
Completá tu cuenta y mantené `us-east-1`. El stack usa el certificado público de
RDS de esa región. No hay contraseñas en las variables.

- Si `dms-vpc-role` ya existe, usá `create_dms_vpc_role = false`.
- Si `dms-cloudwatch-logs-role` ya existe, usá `create_dms_logs_role = false`.
- Verificá que los roles reutilizados confían en `dms.amazonaws.com` y tienen,
  respectivamente, `AmazonDMSVPCManagementRole` y `AmazonDMSCloudWatchLogsRole`
  (o permisos equivalentes). Los roles reutilizados quedan fuera de este estado.
- Dejá **`source_credentials_ready = false`** para la primera aplicación.

Además de crear los recursos del stack, tu identidad necesita `iam:PassRole` y
`iam:GetRole` sobre los roles de endpoints, y `secretsmanager:DescribeSecret`.
El asistente usa STS, Data API, lectura de la credencial administradora a través
de Data API, lectura/escritura del secreto dedicado y los permisos KMS asociados.
No alcanza con poder ejecutar `sts:GetCallerIdentity`.

## 3. Crear la infraestructura y el destino

```sh
terraform -chdir=infra/03-dms init
terraform -chdir=infra/03-dms plan
terraform -chdir=infra/03-dms apply
```

Revisá el plan antes de confirmar. La creación de DMS puede demorar varios minutos.
En esta primera aplicación se crean la instancia, la red, los roles, un secreto
vacío y el endpoint S3. El source endpoint espera a que preparemos sus credenciales.

Explorá en la consola:

- **DMS → Replication instances:** instancia privada `utn-dms-replication`.
- **DMS → Endpoints:** destino `utn-dms-s3-target`.
- **VPC → Endpoints:** S3 de tipo Gateway y los cuatro de tipo Interface.
- **Secrets Manager:** secreto dedicado vacío, sin revelar valores.

DMS tiene una conexión PostgreSQL privada directa a Aurora. Data API se usa para
el asistente y las consultas del participante, no como transporte de replicación.

## 4. Preparar Python para el asistente

Esta etapa agrega **Python 3.10 o posterior**. La instalación se explica en
[la preparación de la web](https://utn.almorgan.dev/#python-dms).
Usamos un entorno virtual local y boto3 con CRT para soportar perfiles creados con
`aws login`. No hace falta instalar `psql`, abrir Aurora a Internet ni copiar
contraseñas. No actives logs de depuración del SDK durante esta operación.

**macOS o Linux:**

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r scripts/requirements.txt
mkdir -p .local
terraform -chdir=infra/03-dms output -raw bootstrap_config > .local/dms-bootstrap.json
.venv/bin/python scripts/prepare_dms_user.py --profile workshop
```

**Windows · PowerShell:**

```powershell
py -3 -m venv .venv
.venv\Scripts\python.exe -m pip install -r scripts/requirements.txt
New-Item -ItemType Directory -Force .local | Out-Null
terraform -chdir=infra/03-dms output -raw bootstrap_config | Set-Content -Encoding ascii .local/dms-bootstrap.json
.venv\Scripts\python.exe scripts/prepare_dms_user.py --profile workshop
```

El JSON local contiene ARNs, host, cuenta y región; no contraseñas. El asistente:

1. Confirma que el perfil corresponde a la cuenta esperada.
2. Genera una contraseña aleatoria y la guarda en el secreto dedicado. Incluye
   `host`, `port`, `username` y `password`, que necesita DMS. El secreto maestro
   administrado por Aurora no tiene el formato necesario para reutilizarlo aquí.
3. Prepara `dms_reader` por Data API usando [`sql/05-dms-user.sql`](../sql/05-dms-user.sql).
   Envía a SQL un verificador SCRAM, no la contraseña en texto plano.
4. Otorga conexión, uso del schema `tienda`, lectura de sus tablas y
   `rds_replication`. No otorga `rds_superuser` ni permisos de escritura de datos.

Ejecutalo de a uno. Si falla después de guardar el secreto, podés repetirlo:
reutiliza la misma credencial y revierte la transacción SQL fallida. Si encuentra
un secreto de otro origen o un rol SQL ajeno al taller, se detiene sin sobrescribirlos.
No hay rotación automática del usuario dedicado en este laboratorio; una operación
permanente necesita su propio mecanismo de rotación. La clave KMS sí rota.

## 5. Crear el endpoint de origen

Después del mensaje de éxito, editá el archivo de variables:

```hcl
source_credentials_ready = true
```

Volvé a revisar y aplicar:

```sh
terraform -chdir=infra/03-dms plan
terraform -chdir=infra/03-dms apply
```

Se agrega `utn-dms-aurora-source`. Conservá la variable en `true`: volverla a
`false` haría que Terraform proponga eliminar ese endpoint.

El source endpoint referencia el ARN del secreto y el rol que puede leerlo.
Usa el certificado público de RDS y `ssl_mode = verify-full`. La captura de DDL
está deshabilitada: trabajamos con las cuatro tablas existentes y cambios de filas,
no con creación o alteración de tablas durante el ejercicio.

## 6. Probar las dos conexiones

Guardá los tres ARNs desde la raíz del repositorio.

**macOS o Linux:**

```sh
dms_instance=$(terraform -chdir=infra/03-dms output -raw replication_instance_arn)
dms_source=$(terraform -chdir=infra/03-dms output -raw source_endpoint_arn)
dms_target=$(terraform -chdir=infra/03-dms output -raw target_endpoint_arn)
```

**Windows · PowerShell:**

```powershell
$dms_instance = terraform -chdir=infra/03-dms output -raw replication_instance_arn
$dms_source = terraform -chdir=infra/03-dms output -raw source_endpoint_arn
$dms_target = terraform -chdir=infra/03-dms output -raw target_endpoint_arn
```

Estos comandos funcionan en ambas terminales:

```sh
aws dms test-connection --replication-instance-arn "$dms_instance" --endpoint-arn "$dms_source" --profile workshop --region us-east-1
aws dms test-connection --replication-instance-arn "$dms_instance" --endpoint-arn "$dms_target" --profile workshop --region us-east-1
aws dms describe-connections --filters "Name=replication-instance-arn,Values=$dms_instance" --query 'Connections[].{Endpoint:EndpointIdentifier,Estado:Status,Error:LastFailureMessage}' --profile workshop --region us-east-1
```

La prueba es asíncrona: repetí la consulta hasta que **ambas conexiones** muestren
`successful`. También podés usar **Test connection** desde cada endpoint en la
consola DMS. No arranques tareas con una conexión fallida.

Un resultado exitoso prueba acceso al endpoint. No prueba todavía la generación
del catálogo, la transferencia completa de datos ni la captura de cambios.

## 7. Reconocer la configuración del catálogo

En el destino S3, identificá estas opciones:

| Opción | Valor del laboratorio |
| --- | --- |
| `DataFormat` | `parquet` |
| `GlueCatalogGeneration` | `true` |
| `IncludeOpForFullLoad` | `true` |
| `TimestampColumnName` | `dms_commit_timestamp` |
| `ParquetTimestampInMillisecond` | `true` |
| `DatePartitionEnabled` | `true` |
| `DatePartitionSequence` / `DatePartitionDelimiter` | `YYYYMMDD` / `SLASH` |

Las particiones por fecha aplican a **CDC**, usando fecha de commit; no particionan
el full load ni son automáticamente el formato Hive `clave=valor`.
El rol de destino puede operar en el bucket del laboratorio, administrar metadatos
Glue en esta cuenta/región y usar workgroups Athena con el prefijo que genera DMS.
Los nombres Glue los decide DMS: en este taller la política cubre las bases y tablas
de la cuenta/región; no es una política para compartir sin revisión en producción.

No se crea un crawler periódico ni un Glue Job. DMS hará la generación de metadatos
cuando se ejecute la tarea. En la etapa 04 verificaremos las tablas y sus ubicaciones;
en CDC, las nuevas particiones. El catálogo describe los archivos, no aplica
actualizaciones/eliminaciones a una tabla materializada de estado actual.

## Si algo falla

- **Faltan outputs o no existe el estado:** aplicá las versiones actualizadas de
  los stacks 01 y 02 en este checkout; no fabriques un estado ni copies IDs ajenos.
- **Cuenta o región no coincide:** corregí el perfil/configuración antes de aplicar.
- **Rol IAM ya existe:** verificá los roles de cuenta y usá la opción de reutilización.
- **InvalidResourceState / instancia creando:** esperá a que DMS esté `available`.
- **AccessDenied al asumir el rol:** revisá confianza, permisos del participante y
  propagación de IAM. El rol de secreto usa el principal regional DMS.
- **Timeout hacia Aurora:** revisá subnets, security groups y puerto 5432. No abras
  el puerto a `0.0.0.0/0` para resolverlo.
- **Error de Secrets Manager:** verificá que el asistente terminó, que el secreto
  tiene versión actual, y la ruta privada/rol/KMS. No pegues su contenido al pedir ayuda.
- **Error de certificado:** comprobá región, hostname y bundle oficial de RDS.
- **Error S3:** revisá cuenta propietaria, región, ruta del gateway y permisos.
- **Error de catálogo en la futura tarea:** revisá Glue/Athena y políticas de la
  cuenta, incluidas restricciones de Lake Formation si están habilitadas.

## Limpieza

Si continuás con full load, conservá los tres stacks. Si terminaste:

1. Si hay tareas posteriores, detenelas y eliminá primero sus recursos según su
   guía. DMS no permite borrar endpoints o instancia mientras una tarea los usa.
2. Destruí el stack DMS:

```sh
terraform -chdir=infra/03-dms plan -destroy
terraform -chdir=infra/03-dms destroy
```

3. Eliminá el usuario SQL dedicado con Data API, usando `.local/aurora.json` de
   la etapa 01 (el secreto administrador sigue existiendo):

```sh
aws rds-data execute-statement --profile workshop --region us-east-1 --cli-input-json file://.local/aurora.json --sql file://sql/06-remove-dms-user.sql
```

4. Seguí la limpieza de S3 y luego de Aurora si cerraste el taller completo.

Terraform elimina los endpoints de red y las reglas que creó; los roles reutilizados
no se modifican. Los roles de cuenta creados por este stack solo deben eliminarse si
no fueron reutilizados por otras cargas. El secreto y la clave KMS quedan programados
para borrado con una ventana de 7 días. El SQL de limpieza no borra tablas; si detecta
dependencias ajenas en el usuario, falla para que las revises.

Las futuras tablas/particiones y workgroups generados por DMS no quedan en este
estado Terraform. Su inspección y limpieza se incorporan al ejercicio de tareas.

## Validación y referencias

Comprobaciones locales: Terraform con AWS y estados anteriores simulados; pruebas
del asistente sin AWS; ejecución SQL y comparación del verificador SCRAM contra
PostgreSQL embebido. Esto no reemplaza un despliegue ni prueba conectividad, cuotas,
IAM efectivo o catálogo real. El ensayo integral en AWS está pendiente.

- [PostgreSQL como origen](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.PostgreSQL.html).
- [Secretos para endpoints DMS](https://docs.aws.amazon.com/dms/latest/userguide/security_iam_secretsmanager.html).
- [SSL en DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.SSL.html).
- [S3 y Glue Data Catalog](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.S3.html).
- [VPC endpoints para DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_VPC_Endpoints.html).
- [Credenciales de login en SDKs](https://docs.aws.amazon.com/sdkref/latest/guide/feature-login-credentials.html).
