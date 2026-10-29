# 06 · Catalogar y consultar

DMS ya escribió Parquet y generó las tablas Glue. No necesitamos un crawler.
Terraform administra las bases vacías de cada ejercicio; DMS administra sus tablas
y metadatos. Athena usa esos metadatos para leer S3: el catálogo no contiene filas.

## Crear un espacio de consultas

Completá `infra/06-athena/terraform.tfvars` desde su ejemplo con los mismos valores
que el resto del laboratorio. La etapa 05 debe estar aplicada.

```sh
terraform -chdir=infra/06-athena init
terraform -chdir=infra/06-athena validate
terraform -chdir=infra/06-athena plan
terraform -chdir=infra/06-athena apply
terraform -chdir=infra/06-athena output
```

Creamos un workgroup propio con Athena engine v3, un bucket privado para resultados
con SSE-S3, y dos consultas guardadas. El workgroup impone la ubicación de resultados
y limita cada consulta a 100 MiB de escaneo. **Ese límite no es un presupuesto ni
elimina costos**. No usamos el workgroup interno que DMS genera para catalogar.

En Athena → Query editor, seleccioná región `us-east-1`, el workgroup que muestra
Terraform, catálogo `AwsDataCatalog` y la base con sufijo `_cdc`. Abrí **Saved
queries**. La identidad que ejecuta las consultas necesita acceso a Athena, Glue
y los buckets del laboratorio; el rol del endpoint DMS no es tu usuario.

## Leer el historial y reconstruir una fila

Ejecutá la consulta **01 - Eventos CDC del producto de prueba**. Para el ID 9001
esperamos tres eventos en orden: `I`, `U`, `D`. Revisá `dms_change_seq`, timestamp
y `$path`, que identifica el archivo físico leído.

Ejecutá **02 - Ultimo evento y estado actual del producto de prueba**. Usa
`row_number()` para elegir primero el último evento por clave y luego descarta los
borrados. Tras ejecutar los tres scripts, debe devolver **cero filas**.

Si filtráramos `op <> 'D'` antes de ordenar, el update anterior reaparecería como
si el producto todavía existiera. El ejercicio está acotado al ID 9001, creado
después de la carga inicial. En este ensayo DMS registró la carga inicial en la
partición `0/0/0`; los cambios llegan a particiones con fecha real. El ejemplo no
implementa una materialización productiva de todo un lakehouse.

Para comprobar la carga inicial, elegí la base con sufijo `_load` de la etapa 04:

```sql
SELECT 'clientes' AS tabla, count(*) AS filas FROM clientes
UNION ALL SELECT 'productos', count(*) FROM productos
UNION ALL SELECT 'pedidos', count(*) FROM pedidos
UNION ALL SELECT 'items_pedido', count(*) FROM items_pedido;
```

Resultado esperado: 5, 6, 8 y 12. Estos datos representan la carga inicial, no los
cambios capturados posteriormente por la otra task.

## Inspeccionar las particiones

Obtené el nombre exacto de la base:

```sh
terraform -chdir=infra/05-cdc output -raw catalog_database
```

Reemplazá `BASE_CDC` en estos comandos:

```sh
aws glue get-table --profile workshop --region us-east-1 --database-name BASE_CDC --name productos --query 'Table.{Columnas:StorageDescriptor.Columns,Particiones:PartitionKeys,Ubicacion:StorageDescriptor.Location}'
aws glue get-partitions --profile workshop --region us-east-1 --database-name BASE_CDC --table-name productos --query 'Partitions[].{Valores:Values,Ubicacion:StorageDescriptor.Location}'
```

Compará tres cosas: la ruta S3, las claves de partición del esquema y los valores
registrados. No inventes nombres de columnas a partir de las carpetas.
Una partición puede apuntar a una ruta sin `clave=valor`: la relación la guarda
Glue. DMS gestiona esta integración; `MSCK REPAIR TABLE` está pensado para
convenciones Hive y no reemplaza ese registro.

En el ensayo, DMS creó las claves string `year`, `month`, `day`. La carga inicial
quedó en `0/0/0`; I/U/D en la fecha UTC del ejercicio. Después de verificar esos
nombres, probá en la base CDC:

```sql
-- Seis productos iniciales.
SELECT count(*) FROM productos
WHERE "year" = '0' AND "month" = '0' AND "day" = '0';

-- Reemplazá la fecha por la partición real: tres eventos del ejercicio.
SELECT op, producto_id, "year", "month", "day", "$path"
FROM productos
WHERE "year" = '2026' AND "month" = '10' AND "day" = '29'
ORDER BY dms_change_seq;
```

Sin filtro de partición, `count(*)` sobre productos devuelve nueve registros:
seis iniciales y tres eventos. Para reconstruir los seis productos vigentes de
este ejercicio, quitá el filtro `producto_id = 9001` de la consulta guardada 02.
Así considera tanto `0/0/0` como los cambios y descarta el producto borrado al final.
No filtres solo el último día para reconstruir todo el estado: perderías la base
y los cambios de días anteriores.

En Athena, compará una consulta sin filtro de fecha con otra que filtre **las
claves de partición reales**. Mirá `Data scanned` y deshabilitá la reutilización
de resultados para la comparación. Si solo hay datos de un día, ambas pueden leer
lo mismo: este dataset pequeño demuestra la selección, no un ahorro medible.
Un filtro sobre `dms_commit_timestamp` no equivale automáticamente a un filtro
sobre las columnas de partición.

## Ejecutar desde CLI (opcional)

Los outputs incluyen IDs de consultas guardadas. Podés obtener el SQL con
`aws athena get-named-query --named-query-id ID`, y enviarlo con
`aws athena start-query-execution --work-group NOMBRE --query-string SQL`.
Agregá `--profile workshop --region us-east-1` en cada comando. Consultá el ID
resultante con `get-query-execution`; solo después de `SUCCEEDED` pedí
`get-query-results`. `FAILED` debe revisarse con su `StateChangeReason`.

Al terminar, seguí [07 · Cerrar el laboratorio](07-limpieza.md).

Referencias: [particiones en Athena](https://docs.aws.amazon.com/athena/latest/ug/partitions.html)
y [integración DMS/S3/Glue](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.S3.html).
