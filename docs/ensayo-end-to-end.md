# Ensayo real de las etapas 01–04

Ejecutado en us-east-1 con Aurora PostgreSQL 16.13, DMS 3.6.1 y provider AWS 6.70.0.
Los datos fueron exclusivamente los ejemplos ficticios del repositorio.

## Resultado funcional

- Aurora privada y Data API: esquema creado y datos cargados.
- Conteos: clientes 5, productos 6, pedidos 8, items_pedido 12.
- Replicación lógica activa, WAL logical y synchronous_commit on.
- SSL obligatorio confirmado en el grupo de parámetros RDS, aplicado in-sync.
- Usuario dedicado preparado dos veces sin mostrar ni rotar su contraseña.
- Source y target endpoint con conexiones successful.
- Task full-load finalizada con FULL_LOAD_ONLY_FINISHED, progreso 100 %, cuatro
  tablas cargadas y cero tablas con error.
- Parquet leído localmente: 31 filas y columnas Op / dms_commit_timestamp.
- Cuatro tablas Glue generadas por DMS, con ubicación en el bucket del ensayo.
- Consulta real Athena sobre el catálogo: conteos 5, 6, 8 y 12 confirmados.
- SQL de limpieza: dms_reader eliminado, cero roles con ese nombre.

No se probó CDC: esa etapa todavía no está implementada. Tampoco se ensayaron
cargas grandes, migración de DDL, recuperación de interrupciones ni concurrencia.

## Correcciones encontradas

1. Aurora no expone rds.force_ssl con current_setting en esta configuración.
   La comprobación SQL fue corregida; SSL se verifica en RDS.
2. DMS rechaza una task full-load si el endpoint tiene DatePartitionEnabled=true.
   La etapa 03 ahora lo deja en false; CDC tendrá su propia configuración.
3. Al modificar el endpoint existente, la API devolvió
   InvalidParameterCombinationException referido a GlueCatalogGeneration y un
   source endpoint. Se recreó únicamente el destino, antes de crear la task,
   y se repitieron las conexiones. No se atribuye una causa definitiva al provider.
4. El secreto usa aws/secretsmanager y recovery_window_in_days=0. No se crea una
   clave KMS propia. La clave administrada ya existía antes del ensayo.
5. Los tests DMS fijan sus variables para aislarse del terraform.tfvars local.

## Identificación y alcance de la limpieza

Se inventariaron 43 recursos administrados por Terraform. Los recursos con soporte
para tags tienen Project, Environment, ManagedBy, Workshop y Stage. Workshop es
el identificador común del ensayo; Stage distingue las etapas.

Los tags del provider no se propagan automáticamente a todos los recursos creados
por AWS. Se identificaron y etiquetaron también recursos secundarios de la VPC,
el secreto administrador de Aurora, la base Glue y el workgroup Athena. Las
asociaciones, reglas internas, streams y metadatos sin tags se rastrean por IDs,
relaciones y ubicaciones. Los roles de cuenta preexistentes se conservaron.

La limpieza de la task no elimina los datos generados. Antes de destruir el bucket
se eliminaron cuatro tablas Glue, su base nueva, el workgroup propio y 27 versiones
u objetos (incluidos resultados Athena). Se comprobó la propiedad del destino
antes de eliminar nada. Terraform luego elimina los stacks y sus recursos.

## Verificación final de limpieza

Los cuatro destroys terminaron: 1 recurso de la task, 23 de DMS, 7 de S3 y 12
de Aurora/red; 43 recursos administrados en total. Los cuatro estados quedaron
sin recursos administrados.

Las APIs de AWS confirmaron ausencia de los recursos propios: clusters, instancias,
subnet/parameter groups, tasks, endpoints, certificados DMS, roles propios, VPC,
subnets, interfaces, security groups, rutas, NACLs, endpoints privados, bucket,
logs, secretos (incluidos los programados para borrado), snapshots y backups
automáticos. La base Glue y el workgroup generados también estaban ausentes.

El índice Resource Groups Tagging API conservaba 15 referencias EC2 al finalizar.
Se consultó cada ID directamente: las 15 devolvieron NotFound. Son referencias
rezagadas del índice, no recursos existentes. Por eso no se usa exclusivamente
la búsqueda por tags como prueba de borrado.

Se conservaron los dos roles DMS preexistentes y la misma clave administrada de
Secrets Manager, habilitada. No se creó una clave KMS propia ni un rol de servicio
adicional. El hosting del workshop permanece fuera del alcance de esta limpieza.
Los registros históricos de auditoría de la cuenta no se eliminan.

## Tiempos observados

- Creación del writer Aurora: 7 min 56 s.
- Creación de la instancia DMS: 8 min 4 s.
- Full load: unos 7 s de carga, además del arranque de la task.
- Eliminación de la instancia DMS: 6 min 40 s.
- Eliminación del writer Aurora: 10 min 8 s.

Son mediciones de este ensayo, no tiempos garantizados. Conviene iniciar los
recursos mientras se explica su función y reservar tiempo para verificar el cierre.

Validación local posterior: 14 tests Terraform y 4 tests del asistente aprobados.
