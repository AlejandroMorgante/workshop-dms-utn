# 07 · Cerrar el laboratorio

Detener una task no elimina la instancia DMS, Aurora ni los endpoints privados.
Cerrar el laboratorio incluye infraestructura, versiones de objetos, resultados
de consultas y recursos creados por DMS fuera del estado Terraform.

**La limpieza es permanente y está pensada exclusivamente para datos descartables
del workshop.** Conservá los estados locales hasta terminar. No mezcles recursos
ajenos en estos buckets o bases Glue y no borres `.local/` antes de verificar.

## Revisar el inventario

Con el entorno Python de la etapa 03 activo, desde la raíz del repositorio:

```sh
python scripts/cleanup_workshop.py --profile workshop --account-id TU_ACCOUNT_ID --workshop-name utn-dms
```

Reemplazá cuenta y nombre por los de tus `terraform.tfvars`. Sin `--apply`, el
asistente **solo consulta e inventaría**; guarda IDs y ARNs en
`.local/cleanup-<workshop_name>.json`, sin contraseñas. Rechaza otra cuenta/región,
tags ajenos o buckets fuera de los tres destinos esperados. Revisá ese archivo.

Las credenciales deben permitir eliminar los mismos recursos que creaste. Si la
sesión venció, renovala antes. No cambies de perfil/cuenta para resolver un error.

## Eliminar el laboratorio

Cuando terminaste las prácticas y guardaste los resultados que necesitás:

```sh
python scripts/cleanup_workshop.py --profile workshop --account-id TU_ACCOUNT_ID --workshop-name utn-dms --apply
```

El asistente:

1. Detiene las tasks registradas y espera que dejen de escribir.
2. Elimina únicamente los workgroups internos derivados de los ARNs de esas tasks.
3. Vacía los buckets propios, incluyendo **versiones, delete markers y cargas
   multipart incompletas**. `aws s3 rm --recursive` solo no alcanza con versionado.
4. Ejecuta Terraform destroy en orden `06 → 05 → 04 → 03 → 02 → 01`.
5. Comprueba estados vacíos y consulta las APIs de servicios con los IDs guardados.

Las bases Glue de 04/05 pertenecen a Terraform; borrarlas elimina también las
tablas y particiones generadas por DMS. Los resultados de Athena están en el bucket
06; los resultados internos de DMS se limpian con los buckets de replicación.
Aurora se elimina sin snapshot final ni backups automáticos retenidos; su secreto
administrado desaparece con el cluster. El secreto dedicado DMS usa borrado sin
recuperación. No creamos una clave KMS propia con eliminación diferida.

El usuario SQL y los slots de replicación desaparecen al eliminar **nuestro
cluster completo**. Si solo vas a retirar DMS y conservar Aurora, no uses este
cierre completo: detené y eliminá las tasks, inspeccioná sus slots inactivos y
retirá solo el usuario/slots propios según la guía 03.

La eliminación puede tardar varios minutos por recurso. Si falla, **no borres los
estados ni el inventario**: resolvé el error y repetí el mismo comando. El manifiesto
conserva los IDs necesarios aunque algunas etapas ya se hayan eliminado.

## Verificar más allá de Terraform

El asistente ejecuta la verificación al terminar. También podés repetirla sin
eliminar nada (por ejemplo, mientras termina un borrado asíncrono):

```sh
python scripts/verify_cleanup.py --profile workshop --manifest .local/cleanup-utn-dms.json
```

Reemplazá el nombre del manifiesto por el de tu ensayo. El informe queda en
`.local/verification-<workshop_name>.json`. Un error de permisos o un recurso
pendiente produce una salida distinta de cero; no lo tomamos como limpieza exitosa.

Estados vacíos son una comprobación, no toda la evidencia. Usá los IDs del
inventario para revisar la cuenta y región del taller:

- RDS: cluster, writer, grupos propios, snapshots y backups retenidos ausentes.
- DMS: tasks, instancia, endpoints, certificado y subnet group ausentes.
- S3: los tres buckets del taller ya no existen.
- Glue: bases `_load` y `_cdc` ausentes; Athena: workgroup de consultas y los dos
  workgroups internos de DMS ausentes. `primary` se conserva.
- Secrets Manager: secreto DMS y secreto del cluster ausentes, incluso entre los
  programados para eliminación. El borrado de secretos puede ser asíncrono.
- CloudWatch Logs e IAM: grupos y roles propios ausentes.
- VPC: red, subnets, interfaces, endpoints, security groups y rutas propias ausentes.

En Resource Groups → Tag Editor buscá `Workshop=<tu nombre>` y
`Project=workshop-dms-utn`. El índice de tags puede devolver ARNs de EC2 ya
eliminados; comprobá esos IDs con la API del servicio. Una referencia antigua no
prueba que el recurso siga activo, y una lista de tags vacía tampoco prueba por sí
sola la limpieza de recursos sin tags.

Los roles de cuenta **reutilizados** `dms-vpc-role` y `dms-cloudwatch-logs-role`,
la clave administrada `aws/secretsmanager`, el perfil CLI y el sitio web del taller
no pertenecen a este despliegue. Si elegiste que Terraform creara los roles DMS en
una cuenta nueva, sí se eliminan con el stack 03.

## Para volver a empezar

Conservá los archivos de código y tus variables locales. El próximo recorrido
empieza por `01-aurora`; requiere cargar nuevamente el esquema, seed y usuario.
Antes de volver a aplicar 03, poné `source_credentials_ready = false` y seguí
otra vez la preparación del usuario. Actualizá el mismo nombre en los seis
archivos de variables.
Usá otro `workshop_name` para un ensayo independiente y no reutilices un manifiesto
de limpieza como si fuera el inventario de un despliegue nuevo.
