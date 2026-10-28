"""Initialize the workshop's dedicated DMS user without printing credentials."""

import argparse
import base64
import hashlib
import hmac
import json
import re
import secrets
import sys
from pathlib import Path

import boto3
from botocore.exceptions import BotoCoreError, ClientError


SQL_PATH = Path(__file__).resolve().parents[1] / "sql" / "05-dms-user.sql"


def scram_verifier(password, salt=None):
    """PostgreSQL SCRAM-SHA-256 storage format (RFC 7677), for an ASCII password."""
    salt = secrets.token_bytes(16) if salt is None else salt
    salted = hashlib.pbkdf2_hmac("sha256", password.encode("ascii"), salt, 4096)
    client = hmac.digest(salted, b"Client Key", "sha256")
    stored = hashlib.sha256(client).digest()
    server = hmac.digest(salted, b"Server Key", "sha256")
    encode = lambda value: base64.b64encode(value).decode("ascii")
    return f"SCRAM-SHA-256$4096:{encode(salt)}${encode(stored)}:{encode(server)}"


def validate_config(config):
    account = config["account_id"]
    region = config["region"]
    if not re.fullmatch(r"\d{12}", account) or region != "us-east-1":
        raise ValueError("La guía de esta etapa requiere cuenta válida y región us-east-1.")
    if config["username"] != "dms_reader" or config["database"] != "workshop":
        raise ValueError("El asistente solo prepara dms_reader en la base workshop.")
    for field, service in [("resource_arn", "rds"), ("admin_secret_arn", "secretsmanager"), ("source_secret_arn", "secretsmanager")]:
        if not config[field].startswith(f"arn:aws:{service}:{region}:{account}:"):
            raise ValueError("Los ARNs deben corresponder a la cuenta y región del laboratorio.")
    if not config["host"].endswith(".rds.amazonaws.com"):
        raise ValueError("El host debe ser el endpoint de Aurora generado por Terraform.")


def prepare(config, sts, sm, data):
    validate_config(config)
    if sts.get_caller_identity()["Account"] != config["account_id"]:
        raise ValueError("El perfil apunta a otra cuenta. No se realizaron cambios.")

    secret_id = config["source_secret_arn"]
    metadata = sm.describe_secret(SecretId=secret_id)
    expected = {"username": "dms_reader", "host": config["host"], "port": 5432,
                "dbname": config["database"], "engine": "postgres"}
    has_current = any("AWSCURRENT" in stages for stages in metadata.get("VersionIdsToStages", {}).values())
    if has_current:
        # Secret values stay in process memory and are never returned to the caller.
        value = json.loads(sm.get_secret_value(SecretId=secret_id)["SecretString"])
        if any(value.get(key) != item for key, item in expected.items()):
            raise ValueError("El secreto existente no corresponde a este laboratorio; no se modificó.")
        password = value["password"]
        if not isinstance(password, str) or not re.fullmatch(r"[A-Za-z0-9_-]{40,}", password):
            raise ValueError("El secreto existente no fue generado por este asistente.")
    else:
        password = secrets.token_urlsafe(36)
        # Persist first: if SQL fails, a retry uses the same credential.
        sm.put_secret_value(SecretId=secret_id, SecretString=json.dumps({**expected, "password": password}))

    request = {"resourceArn": config["resource_arn"], "secretArn": config["admin_secret_arn"],
               "database": config["database"]}
    transaction = data.begin_transaction(**request)["transactionId"]
    try:
        data.execute_statement(**request, transactionId=transaction,
                               sql="SELECT set_config('workshop.dms_verifier', :verifier, true)",
                               parameters=[{"name": "verifier", "value": {"stringValue": scram_verifier(password)}}])
        data.execute_statement(**request, transactionId=transaction, sql=SQL_PATH.read_text())
        data.commit_transaction(resourceArn=request["resourceArn"], secretArn=request["secretArn"], transactionId=transaction)
    except Exception:
        try:
            data.rollback_transaction(resourceArn=request["resourceArn"], secretArn=request["secretArn"], transactionId=transaction)
        except (ClientError, BotoCoreError):
            pass  # Preserve the original error; do not dump SQL or credentials.
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path(".local/dms-bootstrap.json"))
    parser.add_argument("--profile", default="workshop")
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text(encoding="utf-8-sig"))
        validate_config(config)
        session = boto3.Session(profile_name=args.profile, region_name=config["region"])
        prepare(config, session.client("sts"), session.client("secretsmanager"), session.client("rds-data"))
    except ClientError as error:
        print(f"AWS rechazó la preparación ({error.response['Error']['Code']}). Revisá permisos y configuración; podés reintentar.", file=sys.stderr)
        return 1
    except (ValueError, KeyError, OSError, BotoCoreError) as error:
        # Exception messages from SDK/JSON may include request content. Keep them private.
        print(f"No se pudo preparar el usuario ({type(error).__name__}). Verificá perfil, región y archivo de configuración.", file=sys.stderr)
        return 1
    print("Usuario dms_reader preparado. Secreto guardado; no se mostraron credenciales.")
    print("Ahora habilitá source_credentials_ready en Terraform y probá las conexiones.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
