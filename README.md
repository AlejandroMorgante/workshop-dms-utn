# Workshop AWS DMS · UTN

De Aurora PostgreSQL a Amazon S3 con full load y CDC, archivos Parquet,
AWS Glue Data Catalog y consultas con Amazon Athena.

## Prerrequisitos

- Cuenta AWS propia con acceso habilitado y créditos del workshop activados.
- AWS CLI v2, versión 2.32.0 o posterior, instalada y autenticada en esa cuenta.
- Identidad con los permisos necesarios para crear y eliminar los recursos del
  laboratorio. No usamos el usuario raíz.
- Terraform 1.7 o posterior instalado.

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
   y destino.
4. **Full load.** Replicar los datos existentes y revisar los archivos Parquet.
5. **CDC.** Generar inserciones, actualizaciones y eliminaciones para observar
   cómo llegan los cambios al destino.
6. **Catálogo y consultas.** Explorar el registro de metadatos de DMS en Glue,
   las particiones y las consultas con Athena.
7. **Limpieza.** Eliminar los recursos creados y comprobar qué datos permanecen.

## Estado del repositorio

La [etapa 01 · Aurora PostgreSQL](docs/01-aurora.md) incluye la infraestructura
Terraform, los datos de ejemplo y las consultas por Data API. Empezá por esa guía.
Las etapas de S3, DMS, Glue y Athena están pendientes.

```text
infra/01-aurora/     Stack de la etapa 01: red, Aurora y lockfile del provider
  tests/            Comprobaciones de Terraform con AWS simulado
sql/                Esquema, datos ficticios y consultas
docs/01-aurora.md    Pasos del participante y limpieza
```

Cada stack es una carpeta raíz de Terraform con su propio estado. Así podemos
crear una etapa, explorar sus recursos y recién después desplegar la siguiente.
La separación prevista es `01-aurora`, `02-s3` y `03-dms`; por ahora solo está
implementado el primero. Las etapas posteriores recibirán los outputs de las
anteriores, y la limpieza se hará en orden inverso a sus dependencias.

Para validar Terraform sin crear recursos (después de `terraform -chdir=infra/01-aurora init`):

```sh
terraform -chdir=infra/01-aurora fmt -check -recursive
terraform -chdir=infra/01-aurora validate
terraform -chdir=infra/01-aurora test
```

Las pruebas usan un provider simulado; no prueban la creación real de Aurora,
los permisos de una cuenta ni la ejecución de Data API. El ensayo completo en
una cuenta de laboratorio sigue siendo necesario antes del workshop.

La creación del esquema, la carga repetida, las claves, las restricciones y los
totales de las consultas se comprobaron con PostgreSQL embebido (PGlite 0.5.12,
PostgreSQL 18.6). Esa comprobación local no sustituye la prueba en Aurora 16.13
ni valida los parámetros específicos de RDS del archivo `04-verificar.sql`.
