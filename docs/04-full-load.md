# 04 · Cargar las tablas de Aurora en S3

Creamos una task **full load** con Terraform y la arrancamos desde AWS CLI durante
el workshop. El resultado esperado son los datos iniciales en Parquet y sus
metadatos en Glue Data Catalog. La explicación para clase está en
[la web](https://utn.almorgan.dev/etapa-04-full-load.html).

Esta etapa reutiliza la instancia y los endpoints de la etapa 03. No crea otra
instancia DMS, otro bucket ni un crawler. La task se crea detenida: **crear no es
lo mismo que ejecutar**. Ejecutá los comandos desde la raíz del repositorio.

## 1. Confirmar el punto de partida

- Etapas 01, 02 y 03 aplicadas en la misma cuenta y en `us-east-1`.
- Usuario DMS preparado, `source_credentials_ready = true` y ambas conexiones
  con estado `successful`, según [la guía anterior](03-dms.md).
- Las cuatro tablas conservan los datos iniciales. Durante este ejercicio no
  insertes, actualices ni borres filas: el full load aislado no captura cambios
  concurrentes ni garantiza una fotografía consistente de varias tablas activas.
- Usá el destino de este laboratorio, sin otras tasks escribiendo en él.
- Revisá Glue antes de arrancar: en el ensayo DMS generó la base `tienda` y
  tablas con los nombres del origen. Si ya existen tablas ajenas con esos nombres,
  no ejecutes la task sobre ese catálogo sin resolver primero el aislamiento.

```sh
aws sts get-caller-identity --profile workshop
aws rds-data execute-statement --profile workshop --region us-east-1 --cli-input-json file://.local/aurora.json --sql "SELECT 'clientes' AS tabla, count(*) AS filas FROM tienda.clientes UNION ALL SELECT 'productos', count(*) FROM tienda.productos UNION ALL SELECT 'pedidos', count(*) FROM tienda.pedidos UNION ALL SELECT 'items_pedido', count(*) FROM tienda.items_pedido ORDER BY tabla" --include-result-metadata
```

| Tabla | Filas esperadas |
| --- | ---: |
| `tienda.clientes` | 5 |
| `tienda.productos` | 6 |
| `tienda.pedidos` | 8 |
| `tienda.items_pedido` | 12 |
| **Total** | **31** |

Si ya habías desplegado la etapa 03 antes de agregar esta etapa, actualizala:

```sh
terraform -chdir=infra/03-dms plan
terraform -chdir=infra/03-dms apply
```

Esto incorpora los outputs que necesita full load y un grupo CloudWatch Logs con
retención de **7 días**. Su nombre es `dms-tasks-<identificador de la instancia>`;
lo administra el stack 03 porque lo comparten las tasks de esa instancia. Si ya
existía porque ejecutaste una task fuera de esta guía, revisá su propiedad e
importalo al recurso `aws_cloudwatch_log_group.tasks` antes de aplicar; no lo borres
para resolver un conflicto de nombre.

## 2. Leer la task antes de crearla

El stack `infra/04-full-load/` lee los outputs del estado local de `03-dms`.
Rechaza una cuenta/región distinta y un origen todavía sin preparar.

Abrí estos archivos:

- `config/table-mappings.json`: cuatro reglas `explicit`, una por tabla del esquema
  `tienda`. No seleccionamos esquemas completos ni interpretamos el guion bajo de
  `items_pedido` como un comodín.
- `config/task-settings.json`: configuración de carga, errores y logs.

| Opción | Decisión del taller |
| --- | --- |
| `migration_type` | `full-load`: solo datos existentes, sin CDC. |
| `start_replication_task` | `false`: arrancamos manualmente después de inspeccionar. |
| `TargetTablePrepMode` | `DROP_AND_CREATE`: la carga puede reemplazar datos existentes de las tablas seleccionadas en el destino. |
| `MaxFullLoadSubTasks` | 2: hasta dos tablas cargándose a la vez. |
| `CommitRate` | 1000 filas por lote de carga. |
| `SupportLobs` | `false`: el esquema de ejemplo no tiene columnas LOB. |
| Errores de datos, truncamiento o tabla | `STOP_TASK`, para revisar el problema. |
| Logs | Habilitados con severidad predeterminada. |

El formato Parquet y `GlueCatalogGeneration = true` están en el **target endpoint**
creado en la etapa 03. La task decide qué replicar y de qué manera.

## 3. Crear la task

Copiá `infra/04-full-load/terraform.tfvars.example` como
`infra/04-full-load/terraform.tfvars` y completá el ID de tu cuenta. Usá el mismo
perfil, región y prefijo del laboratorio. No copies contraseñas.

```sh
terraform -chdir=infra/04-full-load init
terraform -chdir=infra/04-full-load fmt -check
terraform -chdir=infra/04-full-load validate
terraform -chdir=infra/04-full-load plan
terraform -chdir=infra/04-full-load apply
```

El plan debe agregar **una task**; no otra instancia de replicación. En la consola
DMS, abrí **Database migration tasks** y encontrá `utn-dms-full-load` (o tu prefijo).
Revisá origen, destino, modo y selección de tablas. Esperá el estado `ready`.
Todavía no deberían aparecer archivos nuevos de esta task en S3.

Guardá su ARN y la ubicación del destino en variables de tu terminal.

**macOS / Linux:**

```sh
workshop_task=$(terraform -chdir=infra/04-full-load output -raw replication_task_arn)
workshop_destination=$(terraform -chdir=infra/04-full-load output -raw target_data_uri)
workshop_logs=$(terraform -chdir=infra/04-full-load output -raw task_log_group_name)
```

**PowerShell:**

```powershell
$workshop_task = terraform -chdir=infra/04-full-load output -raw replication_task_arn
$workshop_destination = terraform -chdir=infra/04-full-load output -raw target_data_uri
$workshop_logs = terraform -chdir=infra/04-full-load output -raw task_log_group_name
```

Los comandos siguientes funcionan en ambas terminales.

## 4. Arrancar y observar

Solo la primera vez que ejecutás esta task:

```sh
aws dms start-replication-task --profile workshop --region us-east-1 --replication-task-arn "$workshop_task" --start-replication-task-type start-replication --query 'ReplicationTask.{Id:ReplicationTaskIdentifier,Estado:Status}'
```

La respuesta confirma el pedido, no la carga completa. Repetí esta consulta para
observar el avance; con 31 filas puede finalizar antes de ver estados intermedios:

```sh
aws dms describe-replication-tasks --profile workshop --region us-east-1 --filters "Name=replication-task-arn,Values=$workshop_task" --without-settings --query 'ReplicationTasks[].{Id:ReplicationTaskIdentifier,Estado:Status,Progreso:ReplicationTaskStats.FullLoadProgressPercent,TablasCargadas:ReplicationTaskStats.TablesLoaded,TablasConError:ReplicationTaskStats.TablesErrored,Motivo:StopReason,Error:LastFailureMessage}' --output table
```

Al terminar una carga inicial, `stopped` puede ser normal. Comprobá **todas** las
señales: progreso 100, cuatro tablas cargadas, cero tablas con error y motivo de
parada indicando `FULL_LOAD_ONLY_FINISHED`. `stopped` por sí solo no prueba éxito.

```sh
aws dms describe-table-statistics --profile workshop --region us-east-1 --replication-task-arn "$workshop_task" --query 'TableStatistics[].{Esquema:SchemaName,Tabla:TableName,Estado:TableState,Filas:FullLoadRows,Errores:FullLoadErrorRows}' --output table
```

Deben aparecer exactamente las cuatro tablas, cada una con carga completa, cero
errores y los conteos del paso 1. Si faltan tablas o filas, resolvelo antes de seguir.
Estos conteos son un control del laboratorio, no una comparación exhaustiva del
contenido entre origen y destino.

Los logs están disponibles desde la task o por CLI:

```sh
aws logs tail "$workshop_logs" --profile workshop --region us-east-1 --since 30m --format short
```

El grupo puede contener varias tasks. Identificá el stream de esta task en la
consola antes de atribuirle un mensaje de otro ejercicio.

## 5. Encontrar los Parquet

```sh
aws s3 ls "$workshop_destination" --profile workshop --region us-east-1 --recursive
```

Buscá archivos `LOAD….parquet` dentro de rutas como:

```text
s3://<bucket>/dms/tienda/clientes/LOAD….parquet
s3://<bucket>/dms/tienda/productos/LOAD….parquet
s3://<bucket>/dms/tienda/pedidos/LOAD….parquet
s3://<bucket>/dms/tienda/items_pedido/LOAD….parquet
```

Son ejemplos de estructura, no nombres literales para copiar. DMS decide el número
y nombre de los archivos: una tabla no tiene por qué equivaler a un único objeto.
En S3 revisá tamaño, fecha y cifrado de uno. El JSON de `exploracion/` de la etapa 02
sigue siendo un archivo separado de esta replicación.

**Parquet es un formato columnar binario.** No se inspecciona con `cat`. Podés
esperar a Athena en la etapa 06 o realizar esta práctica local opcional, en el
entorno virtual Python de la etapa 03:

```sh
python -m pip install "pyarrow>=20,<27"
aws s3 cp "s3://REEMPLAZAR_BUCKET/dms/tienda/pedidos/REEMPLAZAR_ARCHIVO.parquet" .local/pedidos.parquet --profile workshop --region us-east-1
python -c "import pyarrow.parquet as pq; p=pq.ParquetFile('.local/pedidos.parquet'); print(p.schema_arrow); print('Filas en este archivo:', p.metadata.num_rows); print(next(p.iter_batches(batch_size=5), None))"
```

Reemplazá la URI por un objeto real del listado. La instalación elige una versión
compatible con tu Python. Mirá tipos, columnas de negocio y metadatos añadidos por
el endpoint, como `dms_commit_timestamp`. El conteo corresponde a **ese archivo**;
si una tabla tiene varios, sumá sus filas. La muestra imprime como máximo cinco.

**Todavía no hay particiones por fecha.** `DatePartitionEnabled` debe quedar
en `false`: DMS rechaza una task `full-load` con esa opción habilitada. Los prefijos por esquema y tabla tampoco son por sí solos
particiones Hive `clave=valor`. Compararemos esos conceptos en la siguiente etapa.

## 6. Comprobar Glue Data Catalog

En la misma región, abrí **AWS Glue → Data Catalog → Databases / Tables**.
Buscá las tablas generadas por la task. No crees un crawler para este ejercicio.
Si no aparecen enseguida, refrescá y revisá los logs; no des por comprobada la
integración solamente porque llegaron archivos a S3.

Para listar bases y luego las tablas de la base que identificaste:

```sh
aws glue get-databases --profile workshop --region us-east-1 --query 'DatabaseList[].Name' --output table
aws glue get-tables --profile workshop --region us-east-1 --database-name REEMPLAZAR_BASE_GLUE --query 'TableList[].{Tabla:Name,Ubicacion:StorageDescriptor.Location,Columnas:StorageDescriptor.Columns,Particiones:PartitionKeys}' --output json
```

DMS genera los nombres: no supongas que la base Glue se llama `workshop` o `tienda`.
Verificá las **ubicaciones S3** y reconocé las cuatro tablas por sus columnas.
Compará los tipos del catálogo con el esquema de Aurora y, si hiciste la práctica
opcional, con Parquet. Guardá los nombres en tus apuntes para consultar con Athena.

El catálogo almacena metadatos; los registros siguen en S3. La integración también
puede crear un workgroup Athena con prefijo `glue_catalog_generation_for_task_`.
Ese workgroup sirve a DMS; prepararemos uno para nuestras consultas en otra etapa.
La identidad del participante necesita permisos de lectura Glue/Logs, además de
operar DMS y S3. El rol del endpoint es otra identidad.

## Si algo falla o querés repetir

- **Faltan outputs:** reaplicá la etapa 03 actualizada con el origen habilitado.
- **Task no arranca:** verificá `ready`, instancia `available` y ambas conexiones
  `successful`; consultá `LastFailureMessage` y los logs.
- **Menos de cuatro tablas:** revisá nombres, esquema, permisos SQL y estadísticas.
- **Archivos sin catálogo:** revisá permisos Glue/Athena del rol de destino,
  endpoints privados y restricciones Lake Formation de la cuenta.
- **Datos distintos a 31 filas:** compará con el origen y revisá cambios realizados
  durante el ejercicio; no recargues a ciegas para ocultar un error.
- **Querés repetir una carga:** `start-replication` es solo para el primer arranque.
  Después, `resume-processing` retoma tablas incompletas y `reload-target` vuelve
  a cargar. Revisá primero los datos del destino: con `DROP_AND_CREATE` una recarga
  puede reemplazarlos. No ejecutes otra task sobre las mismas tablas/destino.
- **Cambiaste settings o mappings en Terraform:** el provider puede detener la
  task para modificarlos. Revisá el plan y hacelo entre ejercicios.

No continuamos este full load con un CDC independiente suponiendo continuidad:
los cambios entre ambas ejecuciones podrían perderse. La etapa 05 preparará una
carga inicial **full load + CDC** y resolverá la separación del destino antes de
arrancar. Esta etapa no implementa todavía ese recorrido.

## Cierre y limpieza

Al completar el ejercicio deberías poder mostrar: task finalizada correctamente,
cuatro estadísticas con 31 filas en total, Parquet en S3 y las cuatro tablas en
Glue apuntando al destino del laboratorio.

Si seguís con el workshop, conservá los recursos. Una task terminada no apaga la
instancia DMS, Aurora ni los endpoints de interfaz: siguen consumiendo.

Si cerrás el laboratorio:

1. Eliminá primero la task (Terraform la detiene si sigue ejecutándose):

```sh
terraform -chdir=infra/04-full-load plan -destroy
terraform -chdir=infra/04-full-load destroy
```

2. En Glue, eliminá **solo** las tablas que verificaste por ubicación como propias
   de este ejercicio. Eliminá la base únicamente si fue creada por el taller y
   quedó vacía. No elimines bases por parecerse sus nombres.
3. En Athena, revisá y eliminá el workgroup generado para esta task si ya no se
   usa. No borres `primary` ni los de otros ejercicios. Revisá su ubicación de
   resultados para incluir sus objetos en la limpieza.
4. Seguí [la limpieza de la etapa 03](03-dms.md#limpieza), luego S3 y Aurora.
   El stack 03 elimina el grupo de logs compartido; guardá antes cualquier evidencia
   que necesites. Para vaciar S3, incluí versiones y delete markers como indica la
   etapa 02.

Destruir la task no elimina automáticamente los objetos S3 ni el catálogo o los
workgroups generados por DMS: no están administrados por este estado Terraform.

## Validación y referencias

Los tests Terraform simulan AWS y el estado anterior: comprueban selección exacta,
arranque manual, manejo de errores y rechazo de dependencias sin preparar o en otra
cuenta/región. No ejecutan una replicación real. El ensayo posterior en AWS
comprobó las 31 filas en Parquet, las cuatro tablas Glue y sus conteos en Athena;
ver [el informe](ensayo-end-to-end.md).

```sh
terraform -chdir=infra/04-full-load test
```

- [Selección de tablas](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TableMapping.SelectionTransformation.Selections.html).
- [Opciones de full load](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TaskSettings.FullLoad.html).
- [Inicio y reanudación](https://docs.aws.amazon.com/dms/latest/APIReference/API_StartReplicationTask.html).
- [Logs de las tasks](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TaskSettings.Logging.html).
- [S3, Parquet, particionado y catálogo](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.S3.html).
- [Lectura local de Parquet](https://arrow.apache.org/docs/python/generated/pyarrow.parquet.ParquetFile.html).
