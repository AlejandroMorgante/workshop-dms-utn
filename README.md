# Workshop AWS DMS · UTN

De Aurora PostgreSQL a Amazon S3 con full load y CDC, archivos Parquet,
AWS Glue Data Catalog y consultas con Amazon Athena.

## Prerrequisitos

- Cuenta AWS propia con acceso habilitado y créditos del workshop activados.
- AWS CLI v2, versión 2.32.0 o posterior, instalada y autenticada en esa cuenta.
- Identidad con los permisos necesarios para crear y eliminar los recursos del
  laboratorio. No usamos el usuario raíz.
- Terraform instalado.

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

Base inicial del taller. La infraestructura Terraform, los SQL y las instrucciones
de cada etapa todavía están pendientes de implementación.
