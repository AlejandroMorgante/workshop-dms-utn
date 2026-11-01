# Workshop AWS DMS · UTN

De Aurora PostgreSQL a Amazon S3 con full load y CDC, archivos Parquet,
AWS Glue Data Catalog y consultas con Amazon Athena.

## Prerrequisitos

- Cuenta AWS propia con acceso habilitado y créditos del workshop activados.
- AWS CLI v2, versión 2.32.0 o posterior, instalada y autenticada en esa cuenta.
- Identidad con los permisos necesarios para crear y eliminar los recursos del
  laboratorio. No usamos el usuario raíz.
- Terraform 1.7 o posterior, menor que 2.0, instalado.
- Para la etapa 03: Python 3.10 o posterior. La preparación en la web incluye
  su instalación; el asistente usa boto3 dentro de un entorno virtual local.

La guía de preparación está publicada en **https://utn.almorgan.dev**.
Allí están las instrucciones de instalación,
autenticación y resolución de problemas. Este repositorio contiene el laboratorio;
no duplica el setup.

## Punto de partida

Los ejemplos usan el perfil `workshop`, el mismo de la guía de preparación.
Si tu perfil tiene otro nombre, reemplazalo en los comandos.

Antes de crear recursos, confirmá la cuenta con la que vas a trabajar:

```sh
aws sts get-caller-identity --profile workshop
terraform version
```

El campo `Account` debe coincidir con la cuenta donde activaste los créditos.
La consulta confirma tu identidad; no comprueba todos los permisos del taller.
Si la sesión venció o falta alguna herramienta, volvé a la guía de preparación.

La región se define al comenzar el laboratorio y se mantiene durante todo el
recorrido. Las credenciales se obtienen del perfil local: no se copian al código,
a archivos de variables ni al repositorio.

## Recorrido del workshop

Vamos a construir el pipeline por etapas, verificando cada resultado en la
consola antes de continuar:

1. **Aurora PostgreSQL.** Crear la base, conectarse, cargar datos y explorar tablas.
2. **Amazon S3.** Preparar el destino y reconocer buckets, prefijos y objetos.
3. **AWS DMS.** Crear la instancia de replicación y probar los endpoints de origen
   y destino, dejando configurada la generación automática de Glue Data Catalog.
4. **Full load.** Replicar los datos existentes y revisar los archivos Parquet.
5. **CDC.** Generar inserciones, actualizaciones y eliminaciones para observar
   cómo llegan los cambios al destino.
6. **Catálogo y consultas.** Explorar el registro de metadatos de DMS en Glue,
   las particiones y las consultas con Athena.
7. **Limpieza.** Eliminar los recursos creados y comprobar qué datos permanecen.

## Estado del repositorio

La [etapa 01 · Aurora PostgreSQL](docs/01-aurora.md) incluye la infraestructura
Terraform, los datos de ejemplo y las consultas por Data API. Empezá por esa guía.
La [etapa 02 · Amazon S3](docs/02-s3.md) agrega el bucket privado y una práctica
de objetos, prefijos y versiones. La [etapa 03 · DMS](docs/03-dms.md) agrega
conectividad privada, endpoints, usuario dedicado y configuración del catálogo.
La [etapa 04 · Full load](docs/04-full-load.md) crea la primera task y guía su
arranque manual, la revisión de Parquet y la comprobación del catálogo.
La [etapa 05 · CDC](docs/05-cdc.md) agrega full load + CDC en un destino separado
con los ejercicios I/U/D. La [etapa 06 · Athena](docs/06-athena.md) crea el workgroup,
resultados privados y consultas guardadas. La [etapa 07 · Limpieza](docs/07-limpieza.md)
cierra el recorrido con inventario, eliminación y verificación.

```text
infra/01-aurora/     Stack de la etapa 01: red, Aurora y lockfile del provider
  tests/            Comprobaciones de Terraform con AWS simulado
infra/02-s3/         Stack de la etapa 02: bucket privado, cifrado y versionado
infra/03-dms/        Stack de la etapa 03: DMS, red, IAM y secreto dedicado
infra/04-full-load/  Stack de la etapa 04: task, selección de tablas y settings
infra/05-cdc/        Stack CDC: destino aislado, catálogo y task full load + CDC
infra/06-athena/     Stack de consultas: workgroup, resultados y SQL guardado
scripts/            Asistente para preparar el usuario SQL de replicación
tests/              Pruebas de los asistentes sin AWS
data/               Archivo JSON para explorar S3
sql/                Esquema, datos ficticios y consultas
docs/01-aurora.md    Etapa 01: pasos y limpieza
docs/02-s3.md        Etapa 02: pasos y limpieza
docs/03-dms.md       Etapa 03: preparación y pruebas de conexión
docs/04-full-load.md Etapa 04: carga inicial, Parquet y catálogo
docs/05-cdc.md       Etapa 05: cambios I/U/D y particiones
docs/06-athena.md    Etapa 06: historial, estado y consultas
docs/07-limpieza.md  Etapa 07: inventario, destroy y verificación
```

Cada stack es una carpeta raíz de Terraform con su propio estado. Así podemos
crear una etapa, explorar sus recursos y recién después desplegar la siguiente.
Los seis stacks, de `01-aurora` a `06-athena`, están implementados. DMS lee los outputs
de los estados locales anteriores; reaplicá los stacks 01 y 02 actualizados antes
de comenzar la etapa 03. Full load lee el estado de DMS: reaplicá la etapa 03
actualizada antes de la 04. La limpieza sigue el orden inverso de dependencias.

Para validar Terraform sin crear recursos (después de `terraform -chdir=infra/01-aurora init`):

```sh
terraform -chdir=infra/01-aurora fmt -check -recursive
terraform -chdir=infra/01-aurora validate
terraform -chdir=infra/01-aurora test
```

Para las etapas 02 a 06, repetí esos comandos con la carpeta correspondiente
(incluido `init`). Los tests de las etapas 03–06 simulan también los
estados previos. Con las dependencias de `scripts/requirements.txt` instaladas,
ejecutá `python -m unittest discover -s tests -v` para probar los asistentes de preparación y limpieza.

Las pruebas usan un provider simulado; no prueban la creación real de Aurora, S3 o DMS,
los permisos de una cuenta, la ejecución de Data API ni las transferencias a S3 o la generación del catálogo. El ensayo real de las etapas 01–04 se ejecutó en `us-east-1`: 31 filas en Parquet,
cuatro tablas Glue generadas por DMS y conteos consultados con Athena.
Los resultados y las correcciones están en [el informe inicial](docs/ensayo-end-to-end.md).
El [ensayo con CDC](docs/ensayo-cdc.md) amplía la prueba a los seis stacks, eventos
I/U/D, particiones y reconstrucción del estado desde Athena. El cierre eliminó
los 66 recursos Terraform y los generados por DMS, con verificación posterior
por APIs de servicios y comprobación de estados vacíos.

La creación del esquema, la carga repetida, las claves, las restricciones y los
totales de las consultas se comprobaron con PostgreSQL embebido (PGlite 0.5.12,
PostgreSQL 18.6). Esa comprobación local no sustituye la prueba en Aurora 16.13
ni valida los parámetros específicos de RDS del archivo `04-verificar.sql`.

El asistente de DMS también se comprobó con PostgreSQL embebido: formato SCRAM
comparado con el generado por PostgreSQL, ejecución repetida, lectura permitida,
escritura rechazada y protección de roles ajenos. La credencial real nunca se
guarda en Terraform ni se imprime.

## Identificación de recursos

Los seis providers aplican los tags comunes `Project=workshop-dms-utn`,
`Environment=workshop`, `ManagedBy=Terraform` y `Workshop=<workshop_name>`.
`Stage` identifica la carpeta de la etapa. Usá un `workshop_name` único por ensayo.
Los recursos que no admiten tags y los creados internamente por AWS necesitan
inventario por IDs y relaciones; los tags por sí solos no prueban una limpieza
completa. Los roles de cuenta reutilizados conservan sus tags y su propietario.

El secreto dedicado usa la clave administrada `aws/secretsmanager` y se destruye
sin recuperación. Este comportamiento está pensado para datos descartables del
workshop. No se crea una clave KMS propia con borrado diferido.

## Licencia

El código, la documentación y la configuración originales de este repositorio
se distribuyen bajo la licencia MIT. El certificado público de Amazon RDS en
`infra/03-dms/certs/us-east-1-bundle.pem` y las marcas de AWS pertenecen a sus
respectivos titulares y no se relicencian mediante esta licencia.
