"""Destroy the disposable workshop, including versioned data and DMS workgroups.

Default is inventory only. --apply requires the exact account and Workshop tag.
The manifest persists IDs across retries; it never contains secret values.
"""
import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import boto3
from botocore.exceptions import BotoCoreError, ClientError

ROOT = Path(__file__).resolve().parents[1]
STAGES = ["01-aurora", "02-s3", "03-dms", "04-full-load", "05-cdc", "06-athena"]


def inventory(root, account, name):
    result = {"account": account, "workshop": name, "region": "us-east-1", "buckets": [], "tasks": [], "resources": [], "data_api": None}
    for stage in STAGES:
        path = root / "infra" / stage / "terraform.tfstate"
        if not path.exists():
            continue
        state = json.loads(path.read_text())
        outputs = state.get("outputs", {})
        context = outputs.get("workshop_context", {}).get("value")
        if context and context != {"account_id": account, "region": "us-east-1"}:
            raise ValueError(f"Estado de {stage} en otra cuenta/región")
        if "data_api_request" in outputs:
            result["data_api"] = json.loads(outputs["data_api_request"]["value"])
        for resource in state.get("resources", []):
            if resource["mode"] != "managed":
                continue
            for instance in resource["instances"]:
                attrs = instance["attributes"]
                tags = attrs.get("tags_all") or attrs.get("tags") or {}
                if tags and (tags.get("Workshop") != name or tags.get("Project") != "workshop-dms-utn"):
                    raise ValueError(f"Recurso de {stage} con tags ajenos: {resource['type']}.{resource['name']}")
                arn_field = {
                    "aws_dms_replication_instance": "replication_instance_arn",
                    "aws_dms_replication_task": "replication_task_arn",
                    "aws_dms_endpoint": "endpoint_arn",
                    "aws_dms_s3_endpoint": "endpoint_arn",
                    "aws_dms_certificate": "certificate_arn",
                }.get(resource["type"], "arn")
                result["resources"].append({"stage": stage, "type": resource["type"], "id": attrs.get("id"), "arn": attrs.get(arn_field)})
                if resource["type"] == "aws_s3_bucket":
                    result["buckets"].append(attrs["id"])
                if resource["type"] == "aws_dms_replication_task":
                    result["tasks"].append(attrs["replication_task_arn"])
    return result


def validate_manifest(manifest, account, name):
    if manifest["account"] != account or manifest["workshop"] != name or manifest["region"] != "us-east-1":
        raise ValueError("El inventario guardado corresponde a otro laboratorio")
    expected = {f"{name}-{kind}-{account}-us-east-1-an" for kind in ("lake", "cdc", "queries")}
    if not set(manifest["buckets"]) <= expected:
        raise ValueError("Bucket fuera del conjunto de destinos del laboratorio")
    for resource in manifest.get("resources", []):
        arn = resource.get("arn")
        if arn and arn.startswith("arn:") and arn.split(":", 5)[4] not in ("", account):
            raise ValueError("El inventario contiene un recurso de otra cuenta")
    for arn in manifest["tasks"]:
        if not re.fullmatch(rf"arn:aws:dms:us-east-1:{account}:task:[A-Za-z0-9]+", arn):
            raise ValueError("ARN de task inválido o de otra cuenta")


def empty_bucket(s3, bucket, account, name):
    try:
        tags = {item["Key"]: item["Value"] for item in s3.get_bucket_tagging(Bucket=bucket, ExpectedBucketOwner=account)["TagSet"]}
    except s3.exceptions.NoSuchBucket:
        return
    if tags.get("Workshop") != name or tags.get("Project") != "workshop-dms-utn":
        raise ValueError(f"No se vacía {bucket}: tags de propietario incorrectos")
    # Delete exact versions, not current keys (which would create delete markers).
    for page in s3.get_paginator("list_object_versions").paginate(Bucket=bucket, ExpectedBucketOwner=account):
        objects = [{"Key": item["Key"], "VersionId": item["VersionId"]} for kind in ("Versions", "DeleteMarkers") for item in page.get(kind, [])]
        for offset in range(0, len(objects), 1000):
            response = s3.delete_objects(Bucket=bucket, ExpectedBucketOwner=account, Delete={"Objects": objects[offset:offset + 1000], "Quiet": True})
            if response.get("Errors"):
                raise RuntimeError(f"No se pudieron eliminar todas las versiones de {bucket}")
    for page in s3.get_paginator("list_multipart_uploads").paginate(Bucket=bucket, ExpectedBucketOwner=account):
        for upload in page.get("Uploads", []):
            s3.abort_multipart_upload(Bucket=bucket, Key=upload["Key"], UploadId=upload["UploadId"], ExpectedBucketOwner=account)


def stop_tasks(dms, tasks):
    for arn in tasks:
        deadline = time.monotonic() + 600
        while True:
            try:
                tasks_found = dms.describe_replication_tasks(Filters=[{"Name": "replication-task-arn", "Values": [arn]}], WithoutSettings=True)["ReplicationTasks"]
                if not tasks_found:
                    break
                task = tasks_found[0]
            except dms.exceptions.ResourceNotFoundFault:
                break
            status = task["Status"]
            if status in ("stopped", "ready", "failed"):
                break
            if status == "running":
                dms.stop_replication_task(ReplicationTaskArn=arn)
            if time.monotonic() > deadline:
                raise RuntimeError(f"La task no se detuvo: {arn} ({status})")
            time.sleep(10)


def remove_workgroups(athena, manifest):
    for arn in manifest["tasks"]:
        name = "glue_catalog_generation_for_task_" + arn.rsplit(":", 1)[1]
        # get_work_group returns InvalidRequestException for a missing workgroup.
        # Use the CLI paginator for this API (boto3 has no list_work_groups paginator).
        names = json.loads(subprocess.check_output(["aws", "athena", "list-work-groups", "--profile", manifest["profile"], "--region", "us-east-1", "--output", "json"]))["WorkGroups"]
        if name not in {item["Name"] for item in names}:
            continue
        group = athena.get_work_group(WorkGroup=name)["WorkGroup"]
        location = group["Configuration"].get("ResultConfiguration", {}).get("OutputLocation", "")
        if location and location.split("/")[2] not in manifest["buckets"]:
            raise ValueError(f"Workgroup {name} apunta a un bucket ajeno; revisar antes de borrar")
        athena.delete_work_group(WorkGroup=name, RecursiveDeleteOption=True)


def run(args):
    if not re.fullmatch(r"\d{12}", args.account_id) or not re.fullmatch(r"[a-z][a-z0-9-]{1,18}[a-z0-9]", args.workshop_name) or "--" in args.workshop_name:
        raise ValueError("Cuenta o nombre de workshop inválido")
    session = boto3.Session(profile_name=args.profile, region_name="us-east-1")
    if session.client("sts").get_caller_identity()["Account"] != args.account_id:
        raise ValueError("El perfil está autenticado en otra cuenta")
    current = inventory(ROOT, args.account_id, args.workshop_name)
    path = ROOT / ".local" / f"cleanup-{args.workshop_name}.json"
    manifest = json.loads(path.read_text()) if path.exists() else current
    validate_manifest(manifest, args.account_id, args.workshop_name)
    # Merge newly created stages while retaining identifiers from earlier attempts.
    for key in ("buckets", "tasks", "resources"):
        for item in current[key]:
            if item not in manifest[key]:
                manifest[key].append(item)
    manifest["profile"] = args.profile
    if current["data_api"]:
        manifest["data_api"] = current["data_api"]
    validate_manifest(manifest, args.account_id, args.workshop_name)
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2))
    print(f"Inventario: {path}\nRecursos registrados: {len(manifest['resources'])}\nBuckets: {manifest['buckets']}\nTasks: {manifest['tasks']}", flush=True)
    if not args.apply:
        print("Solo inventario. Revisalo; --apply elimina permanentemente este laboratorio.")
        return
    stop_tasks(session.client("dms"), manifest["tasks"])
    remove_workgroups(session.client("athena"), manifest)
    s3 = session.client("s3")
    for bucket in manifest["buckets"]:
        empty_bucket(s3, bucket, args.account_id, args.workshop_name)
    for stage in reversed(STAGES):
        if not any(item["stage"] == stage for item in current["resources"]):
            continue
        print(f"Destruyendo {stage}", flush=True)
        subprocess.run(["terraform", f"-chdir={ROOT / 'infra' / stage}", "destroy", "-auto-approve", "-input=false", f"-var=aws_profile={args.profile}", f"-var=expected_account_id={args.account_id}", "-var=aws_region=us-east-1", f"-var=workshop_name={args.workshop_name}"], check=True)
    remaining = inventory(ROOT, args.account_id, args.workshop_name)["resources"]
    if remaining:
        raise RuntimeError("Quedan recursos administrados en los estados Terraform")
    print("Estados Terraform vacíos. Verificando APIs de servicios...", flush=True)
    subprocess.run([sys.executable, str(ROOT / "scripts/verify_cleanup.py"), "--manifest", str(path), "--profile", args.profile], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default="workshop")
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--workshop-name", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        run(args)
    except (ValueError, RuntimeError, ClientError, BotoCoreError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
