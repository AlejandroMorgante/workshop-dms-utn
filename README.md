# Workshop AWS DMS · UTN

Replicamos datos de Aurora PostgreSQL a Amazon S3 con AWS DMS. Exploramos Full Load,
CDC, Parquet, Glue Data Catalog y consultas con Athena.

[Ver el recorrido del workshop](https://utn.almorgan.dev/workshop/) ·
[Preparar la cuenta y las herramientas](https://utn.almorgan.dev/)

<table align="center">
  <tr>
    <td align="center"><img src="docs/assets/icons/aurora.svg" width="64" alt="Amazon Aurora"><br><strong>Aurora PostgreSQL</strong></td>
    <td align="center">→</td>
    <td align="center"><img src="docs/assets/icons/dms.svg" width="64" alt="AWS DMS"><br><strong>AWS DMS</strong></td>
    <td align="center">→</td>
    <td align="center"><img src="docs/assets/icons/s3.svg" width="64" alt="Amazon S3"><br><strong>Amazon S3</strong></td>
  </tr>
  <tr>
    <td colspan="5" align="center">DMS registra las tablas en el catálogo de Glue; Athena consulta los datos de S3 usando ese catálogo.</td>
  </tr>
  <tr>
    <td colspan="2" align="center"><img src="docs/assets/icons/glue.svg" width="64" alt="AWS Glue Data Catalog"><br><strong>Glue Data Catalog</strong></td>
    <td align="center">→</td>
    <td colspan="2" align="center"><img src="docs/assets/icons/athena.svg" width="64" alt="Amazon Athena"><br><strong>Amazon Athena</strong></td>
  </tr>
</table>

## Requisitos

- Cuenta AWS dedicada al laboratorio, con créditos activos e identidad con MFA.
- AWS CLI 2.32.0 o posterior y Terraform 1.7 o posterior, menor que 2.0.
- Python 3.10 o posterior para preparar el usuario de DMS en la etapa 03.

No uses el usuario raíz. El laboratorio crea recursos con costo; completá la
[limpieza](docs/07-limpieza.md) al terminar.

## Etapas

| Etapa | Guía |
| --- | --- |
| 01 · Aurora PostgreSQL | [Base y datos de ejemplo](docs/01-aurora.md) |
| 02 · Amazon S3 | [Bucket, objetos y versiones](docs/02-s3.md) |
| 03 · AWS DMS | [Instancia, endpoints y catálogo](docs/03-dms.md) |
| 04 · Full Load | [Carga inicial y Parquet](docs/04-full-load.md) |
| 05 · CDC | [Cambios y particiones](docs/05-cdc.md) |
| 06 · Glue y Athena | [Catálogo y consultas](docs/06-athena.md) |
| 07 · Cierre | [Eliminar y verificar recursos](docs/07-limpieza.md) |

Los stacks de `infra/01-aurora/` a `infra/06-athena/` tienen estados Terraform
separados. Seguí las guías en orden y conservá los estados hasta completar la
limpieza. Aurora y S3 pueden prepararse en paralelo.

Confirmá la cuenta y el perfil antes de desplegar:

```sh
aws sts get-caller-identity --profile workshop
terraform version
```

## Validación

Las pruebas locales usan AWS simulado; no crean recursos. Consultá cada guía
para los comandos de Terraform y Python. El ensayo end-to-end está documentado en
[`docs/ensayo-cdc.md`](docs/ensayo-cdc.md).

## Licencia

El código, la documentación y la configuración originales se distribuyen bajo
la licencia [MIT](LICENSE). Los iconos y marcas de AWS, y el certificado
público de Amazon RDS, pertenecen a sus respectivos titulares y no se
relicencian aquí.
