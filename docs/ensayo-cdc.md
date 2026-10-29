# Ensayo end-to-end · Full load, CDC y Athena

Fecha local: 28 de octubre de 2026 (29 de octubre UTC). Región: `us-east-1`.
Perfil del ensayo: `snail-data`. Datos sintéticos; despliegue aislado con un
`workshop_name` exclusivo. No se reutilizaron buckets, catálogos ni tasks anteriores.

## Infraestructura y origen

Se desplegaron los seis stacks en orden. Aurora PostgreSQL 16.13, DMS 3.6.1,
Terraform 1.14.4 y AWS provider 6.70.0. El writer tardó 7m35s en crearse;
la instancia DMS, 8m57s. Son tiempos observados, no garantías de servicio.

Se verificaron `rds.force_ssl=1`, `rds.logical_replication=1`, parámetros in-sync,
`wal_level=logical`, Data API y conexiones DMS de origen/destino successful.
Se preparó el usuario dedicado sin imprimir ni guardar su contraseña en Terraform.

## Full load y aislamiento

La task full-load terminó con 100 %, cuatro tablas, cero errores y
`FULL_LOAD_ONLY_FINISHED`. Se leyeron los Parquet: clientes 5, productos 6,
pedidos 8 e items_pedido 12; total 31.

Terraform creó una base Glue vacía con sufijo `_load`; DMS generó sus cuatro
tablas. La transformación del esquema también se reflejó en las rutas S3.
El esquema PostgreSQL siguió siendo `tienda`.

## CDC y particiones

La task full-load-and-cdc usó la misma instancia, pero otro bucket, endpoint y
base Glue con sufijo `_cdc`. Completó sus 31 filas iniciales y siguió running.

Con `DatePartitionEnabled=true` y `GlueCatalogGeneration=true`, DMS registró
columnas string `year`, `month`, `day`. Los Parquet de full load quedaron en
`0/0/0/LOAD….parquet`, con partición registrada `['0','0','0']`. Los eventos se
organizaron por fecha UTC. Es una estructura no Hive: no tiene `clave=valor` en
la ruta, pero Glue conoce sus valores y ubicaciones.

Se ejecutaron los tres SQL por separado, esperando su llegada a Parquet:
insert del producto 9001 a $100, update a $125/stock 9 y delete. La expresión
`$AR_H_CHANGE_SEQ` produjo secuencias de 35 dígitos para ordenar los eventos;
la carga inicial tenía secuencia vacía. El delete conservó la clave y dejó
las demás columnas de negocio en null. Los tipos de Parquet coincidieron entre
carga y CDC, incluido `decimal(12,2)` para precio.

## Consultas y cierre

Se ejecutaron seis consultas con estado `SUCCEEDED`:

| Consulta | Resultado |
| --- | --- |
| Historial del producto 9001 | I, U, D en orden; precios 100, 125, null |
| Último evento del producto 9001, excluyendo borrados al final | 0 filas |
| Registros crudos de productos | 9: seis iniciales + tres eventos |
| Estado de todos los productos del ejercicio | 6 claves, del 1 al 6 |
| Conteos de la base full load | 5, 6, 8, 12 |
| Filtro year/month/day de CDC | 3 eventos |

Aurora confirmó seis productos y cero filas con ID 9001. Algunas consultas de
conteo reportaron cero bytes escaneados por optimización del motor; no usamos
este dataset pequeño para afirmar un ahorro de costos.

El asistente de cierre eliminó los 66 recursos administrados por Terraform:
06=10, 05=12, 04=2, 03=23, 02=7 y 01=12. También vació versiones y delete markers
de los tres buckets y eliminó los dos workgroups internos de DMS. Las bases Glue
propias se eliminaron con sus tablas y particiones.

La eliminación de la instancia DMS tardó 6m39s y la del writer Aurora, 9m7s.
La verificación por APIs confirmó ausencia de clusters, instancias, snapshots,
backups retenidos, secretos (incluidos los programados para eliminación), buckets,
catálogos, workgroups propios, roles propios, logs y recursos de la VPC.
Los seis estados quedaron vacíos.

El índice de tags conservaba diez referencias EC2: se consultó cada ID y la API
respondió NotFound. No se contaron como recursos activos. La comprobación
intermedia, mientras Aurora se eliminaba, sí detectó los recursos aún presentes;
el verificador no aprobó el cierre antes de tiempo. Se repitió el comando completo
con `--apply` después de la limpieza: terminó correctamente, sin recursos nuevos
para eliminar ni cambios sobre los compartidos.

Se conservaron los roles DMS reutilizados y la clave administrada de Secrets
Manager. El sitio del workshop pertenece a otro despliegue y siguió disponible.
La evidencia técnica local queda en `.local/cdc-e2e/` y en los manifiestos
`.local/cleanup-<nombre>.json` / `.local/verification-<nombre>.json`, fuera de Git.

## Comprobaciones del código y publicación

Pasaron 20 pruebas Terraform con AWS simulado y 10 pruebas Python de los asistentes.
Se revisaron formato, sintaxis y enlaces locales. Las nueve páginas del sitio
pasaron el control de enlaces, assets e IDs. La PR 17 del sitio se integró y el
despliegue Amplify 8 terminó SUCCEED; las ocho páginas públicas comprobadas
respondieron HTTP 200 con contenido idéntico a main.
La automatización de navegador no estuvo disponible para una revisión visual
interactiva; se reutilizó el diseño existente.
