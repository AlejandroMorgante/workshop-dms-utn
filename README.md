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
CDC y las consultas Athena quedan para las etapas siguientes.

```text
infra/01-aurora/     Stack de la etapa 01: red, Aurora y lockfile del provider
  tests/            Comprobaciones de Terraform con AWS simulado
infra/02-s3/         Stack de la etapa 02: bucket privado, cifrado y versionado
infra/03-dms/        Stack de la etapa 03: DMS, red, IAM y secreto dedicado
infra/04-full-load/  Stack de la etapa 04: task, selección de tablas y settings
scripts/            Asistente para preparar el usuario SQL de replicación
tests/              Pruebas del asistente sin AWS
data/               Archivo JSON para explorar S3
sql/                Esquema, datos ficticios y consultas
docs/01-aurora.md    Etapa 01: pasos y limpieza
docs/02-s3.md        Etapa 02: pasos y limpieza
docs/03-dms.md       Etapa 03: preparación y pruebas de conexión
docs/04-full-load.md Etapa 04: carga inicial, Parquet y catálogo
```

Cada stack es una carpeta raíz de Terraform con su propio estado. Así podemos
crear una etapa, explorar sus recursos y recién después desplegar la siguiente.
Los stacks `01-aurora`, `02-s3`, `03-dms` y `04-full-load` están implementados. DMS lee los outputs
de los estados locales anteriores; reaplicá los stacks 01 y 02 actualizados antes
de comenzar la etapa 03. Full load lee el estado de DMS: reaplicá la etapa 03
actualizada antes de la 04. La limpieza sigue el orden inverso de dependencias.

Para validar Terraform sin crear recursos (después de `terraform -chdir=infra/01-aurora init`):

```sh
terraform -chdir=infra/01-aurora fmt -check -recursive
terraform -chdir=infra/01-aurora validate
terraform -chdir=infra/01-aurora test
```

Para las etapas 02, 03 y 04, repetí esos comandos con la carpeta correspondiente
(incluido `init`). Los tests de DMS y full load simulan también los
estados previos. Con las dependencias de `scripts/requirements.txt` instaladas,
ejecutá `python -m unittest discover -s tests -v` para probar el asistente.

Las pruebas usan un provider simulado; no prueban la creación real de Aurora, S3 o DMS,
los permisos de una cuenta, la ejecución de Data API ni las transferencias a S3 o la generación del catálogo. El ensayo completo en
una cuenta de laboratorio sigue siendo necesario antes del workshop.

La creación del esquema, la carga repetida, las claves, las restricciones y los
totales de las consultas se comprobaron con PostgreSQL embebido (PGlite 0.5.12,
PostgreSQL 18.6). Esa comprobación local no sustituye la prueba en Aurora 16.13
ni valida los parámetros específicos de RDS del archivo `04-verificar.sql`.

El asistente de DMS también se comprobó con PostgreSQL embebido: formato SCRAM
comparado con el generado por PostgreSQL, ejecución repetida, lectura permitida,
escritura rechazada y protección de roles ajenos. La credencial real nunca se
guarda en Terraform ni se imprime.
