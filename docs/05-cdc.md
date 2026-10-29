# 05 · Capturar los cambios con CDC

Partimos de las etapas 01–04 completas, en la misma cuenta y región. El full load
anterior debe estar terminado. Esta etapa crea **otra task, full load + CDC**, en
la misma instancia DMS. Hace su propia carga inicial y luego continúa leyendo el
log de PostgreSQL: no intentamos conectar dos ejecuciones separadas suponiendo
que no hubo cambios en el medio.

## Preparar el destino y la task

El stack `infra/05-cdc/` agrega un bucket privado y versionado exclusivo, un rol de
escritura, un endpoint S3 y la task. Terraform crea una base Glue vacía con nombre
`<workshop_name_con_guiones_bajos>_cdc`; DMS genera las tablas y sus metadatos.
La transformación cambia el esquema **en el destino**, no el esquema `tienda` de
Aurora. No compartimos bucket ni catálogo con el ejercicio full load.

Copiá `terraform.tfvars.example` a `terraform.tfvars` dentro del stack y completá
la misma cuenta, perfil, región y `workshop_name` que en las etapas anteriores.

```sh
terraform -chdir=infra/05-cdc init
terraform -chdir=infra/05-cdc validate
terraform -chdir=infra/05-cdc plan
terraform -chdir=infra/05-cdc apply
```

La task se crea sin arrancar. En DMS revisá que sea **Migrate existing data and
replicate ongoing changes**, con las cuatro tablas exactas de `tienda`.
Esperá `ready`. Los endpoints deben poder conectarse.

macOS / Linux:

```sh
workshop_cdc=$(terraform -chdir=infra/05-cdc output -raw replication_task_arn)
workshop_cdc_uri=$(terraform -chdir=infra/05-cdc output -raw target_data_uri)
workshop_catalog=$(terraform -chdir=infra/05-cdc output -raw catalog_database)
```

PowerShell:

```powershell
$workshop_cdc = terraform -chdir=infra/05-cdc output -raw replication_task_arn
$workshop_cdc_uri = terraform -chdir=infra/05-cdc output -raw target_data_uri
$workshop_catalog = terraform -chdir=infra/05-cdc output -raw catalog_database
```

En ambas terminales, el primer arranque es:

```sh
aws dms start-replication-task --profile workshop --region us-east-1 --replication-task-arn "$workshop_cdc" --start-replication-task-type start-replication --query 'ReplicationTask.{Id:ReplicationTaskIdentifier,Estado:Status}'
aws dms describe-replication-tasks --profile workshop --region us-east-1 --filters "Name=replication-task-arn,Values=$workshop_cdc" --without-settings --query 'ReplicationTasks[].{Estado:Status,Progreso:ReplicationTaskStats.FullLoadProgressPercent,Tablas:ReplicationTaskStats.TablesLoaded,Errores:ReplicationTaskStats.TablesErrored,Falla:LastFailureMessage}'
aws dms describe-table-statistics --profile workshop --region us-east-1 --replication-task-arn "$workshop_cdc" --query 'TableStatistics[].{Tabla:TableName,Iniciales:FullLoadRows,Insertadas:Inserts,Actualizadas:Updates,Borradas:Deletes,Estado:TableState}' --output table
```

Esperá 100 %, cuatro tablas, 31 filas iniciales y cero errores. Esta vez la task
**permanece `running`** para capturar cambios. No confundas CDC activo con una carga
inicial incompleta. No modifiques las tablas hasta verificar ese punto.

## Una fila, tres operaciones

Usamos el producto `9001`, que no existe en el seed. Cada llamada Data API confirma
su propia transacción. Ejecutá **un comando por vez**; mirá Aurora, las estadísticas
DMS y S3 antes de pasar al siguiente. El endpoint configura lotes CDC de hasta
60 segundos; el catálogo puede tardar más. No es una promesa de latencia máxima.

```sh
aws rds-data execute-statement --profile workshop --region us-east-1 --cli-input-json file://.local/aurora.json --sql file://sql/07-cdc-insert.sql
```

```sh
aws rds-data execute-statement --profile workshop --region us-east-1 --cli-input-json file://.local/aurora.json --sql file://sql/08-cdc-update.sql
```

```sh
aws rds-data execute-statement --profile workshop --region us-east-1 --cli-input-json file://.local/aurora.json --sql file://sql/09-cdc-delete.sql
```

El insert crea un producto de $100; el update cambia su precio a $125 y el stock a
9; el delete lo elimina. Los scripts fallan si no se cumple el orden esperado.
No los ejecutes juntos dentro de una única transacción ni repitas a ciegas.

```sh
aws rds-data execute-statement --profile workshop --region us-east-1 --cli-input-json file://.local/aurora.json --sql "SELECT count(*) AS productos, count(*) FILTER (WHERE producto_id = 9001) AS demo FROM tienda.productos"
aws s3 ls "$workshop_cdc_uri" --profile workshop --region us-east-1 --recursive
aws glue get-tables --profile workshop --region us-east-1 --database-name "$workshop_catalog" --query 'TableList[].{Tabla:Name,Ubicacion:StorageDescriptor.Location,Particiones:PartitionKeys}'
```

Resultado en Aurora: seis productos, cero filas con ID 9001. En S3 buscamos el
historial de operaciones `I`, `U`, `D`, no un archivo que se haya reducido a seis
filas. En el borrado observado viajó la clave 9001; las otras columnas de negocio
quedaron en null. No dependemos de ellas para interpretar el delete. En la etapa 06 lo consultamos con SQL.

## Fecha, partición y orden

- `DatePartitionEnabled=true`, `YYYYMMDD`, `SLASH`, UTC: los archivos CDC se
  organizan en directorios de fecha. Con catálogo automático, en el ensayo la
  carga inicial quedó en `0/0/0/LOAD….parquet`, registrada como la partición
  `year=0`, `month=0`, `day=0`. Inspeccioná siempre las ubicaciones reales.
- Una ruta `2026/10/29/` **no es Hive** `year=2026/month=10/day=29/`. Athena puede
  usar particiones no Hive si sus valores y ubicaciones están registrados.
  No usamos `MSCK REPAIR TABLE` para inferir estas rutas.
- `dms_commit_timestamp` ayuda a observar tiempos; no alcanza para desempatar
  eventos con el mismo timestamp. Agregamos `dms_change_seq` con la expresión DMS
  `$AR_H_CHANGE_SEQ`, una secuencia de 35 dígitos para ordenar cambios de esta
  task. En full load puede estar vacía. No es un orden global entre distintas tasks.
- Los Parquet son eventos append-only. Para obtener estado actual hay que aplicar
  operaciones en orden y respetar los borrados. Este taller no implementa una tabla
  Iceberg ni un proceso productivo de compactación/deduplicación.

## Si algo falla

Revisá `LastFailureMessage`, estadísticas por tabla y el stream de la task en
CloudWatch. Un problema de permisos de Glue puede dejar archivos correctos sin
catálogo actualizado. Un origen con CDC detenido puede retener WAL: al terminar,
seguí [07 · Cierre](07-limpieza.md), no dejes Aurora y DMS encendidos indefinidamente.
Si ya arrancaste la task, `start-replication` no se reutiliza: para retomar una
pausa revisá el checkpoint y usá `resume-processing`. Recargar tiene efectos sobre
el destino y requiere reiniciar el ejercicio de manera controlada.

Siguiente: [06 · Catálogo y consultas](06-athena.md).

Referencias: [DMS con S3](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.S3.html),
[expresiones de transformación](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TableMapping.SelectionTransformation.Expressions.html)
y [PostgreSQL como origen](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.PostgreSQL.html).
