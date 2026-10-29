"""Read-only verification of a cleanup manifest using AWS service APIs."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def verify(manifest, profile):
    def aws(*args):
        return json.loads(subprocess.check_output(["aws", *args, "--profile", profile, "--region", manifest["region"], "--output", "json"]))

    if aws("sts", "get-caller-identity")["Account"] != manifest["account"]:
        raise ValueError("El perfil apunta a otra cuenta")
    prefix = manifest["workshop"]
    resources = manifest["resources"]
    report = {}

    def check(label, items):
        report[label] = items
        print(f"{label}: {len(items)}", flush=True)

    def ids(kind):
        return {r["id"] for r in resources if r["type"] == kind}

    # CLI auto-pagination handles services without boto3 paginators as well.
    services = [
        ("rds", "describe-db-clusters", "DBClusters", "DBClusterIdentifier", "aws_rds_cluster"),
        ("rds", "describe-db-instances", "DBInstances", "DBInstanceIdentifier", "aws_rds_cluster_instance"),
        ("rds", "describe-db-subnet-groups", "DBSubnetGroups", "DBSubnetGroupName", "aws_db_subnet_group"),
        ("rds", "describe-db-cluster-parameter-groups", "DBClusterParameterGroups", "DBClusterParameterGroupName", "aws_rds_cluster_parameter_group"),
        ("dms", "describe-replication-instances", "ReplicationInstances", "ReplicationInstanceArn", "aws_dms_replication_instance"),
        ("dms", "describe-endpoints", "Endpoints", "EndpointArn", "aws_dms_endpoint"),
        ("dms", "describe-endpoints", "Endpoints", "EndpointArn", "aws_dms_s3_endpoint"),
        ("dms", "describe-replication-tasks", "ReplicationTasks", "ReplicationTaskArn", "aws_dms_replication_task"),
        ("dms", "describe-replication-subnet-groups", "ReplicationSubnetGroups", "ReplicationSubnetGroupIdentifier", "aws_dms_replication_subnet_group"),
        ("dms", "describe-certificates", "Certificates", "CertificateArn", "aws_dms_certificate"),
        ("iam", "list-roles", "Roles", "RoleName", "aws_iam_role"),
    ]
    for service, operation, key, field, kind in services:
        owned = ids(kind) | {r["arn"] for r in resources if r["type"] == kind and r.get("arn")}
        check(kind, [r[field] for r in aws(service, operation)[key] if r[field] in owned])
    for vpc in ids("aws_vpc"):
        for operation, key in [("describe-network-interfaces", "NetworkInterfaces"), ("describe-subnets", "Subnets"), ("describe-security-groups", "SecurityGroups"), ("describe-route-tables", "RouteTables"), ("describe-network-acls", "NetworkAcls"), ("describe-vpc-endpoints", "VpcEndpoints"), ("describe-vpcs", "Vpcs")]:
            check(f"{vpc}/{operation}", aws("ec2", operation, "--filters", f"Name=vpc-id,Values={vpc}")[key])
    check("buckets", [r["Name"] for r in aws("s3api", "list-buckets")["Buckets"] if r["Name"] in manifest["buckets"]])
    for operation, key, field, owned in [
        ("describe-db-cluster-snapshots", "DBClusterSnapshots", "DBClusterIdentifier", ids("aws_rds_cluster")),
        ("describe-db-cluster-automated-backups", "DBClusterAutomatedBackups", "DBClusterIdentifier", ids("aws_rds_cluster")),
        ("describe-db-snapshots", "DBSnapshots", "DBInstanceIdentifier", ids("aws_rds_cluster_instance")),
        ("describe-db-instance-automated-backups", "DBInstanceAutomatedBackups", "DBInstanceIdentifier", ids("aws_rds_cluster_instance")),
    ]:
        check(operation, [r[field] for r in aws("rds", operation)[key] if r.get(field) in owned])
    check("logs", [r["logGroupName"] for r in aws("logs", "describe-log-groups")["logGroups"] if r["logGroupName"] in ids("aws_cloudwatch_log_group")])
    secrets = ids("aws_secretsmanager_secret")
    if manifest.get("data_api"):
        secrets.add(manifest["data_api"]["secretArn"])
    check("secrets_including_planned_deletion", [r["ARN"] for r in aws("secretsmanager", "list-secrets", "--include-planned-deletion")["SecretList"] if r["ARN"] in secrets])
    databases = {prefix.replace("-", "_") + suffix for suffix in ("_load", "_cdc")}
    check("glue", [r["Name"] for r in aws("glue", "get-databases")["DatabaseList"] if r["Name"] in databases])
    groups = {"glue_catalog_generation_for_task_" + arn.rsplit(":", 1)[1] for arn in manifest["tasks"]} | {prefix + "-queries"}
    check("athena", [r["Name"] for r in aws("athena", "list-work-groups")["WorkGroups"] if r["Name"] in groups])
    stale = []
    active = []
    ec2_types = {
        "vpc": ("describe-vpcs", "--vpc-ids"),
        "subnet": ("describe-subnets", "--subnet-ids"),
        "security-group": ("describe-security-groups", "--group-ids"),
        "security-group-rule": ("describe-security-group-rules", "--security-group-rule-ids"),
        "route-table": ("describe-route-tables", "--route-table-ids"),
        "vpc-endpoint": ("describe-vpc-endpoints", "--vpc-endpoint-ids"),
        "network-interface": ("describe-network-interfaces", "--network-interface-ids"),
    }
    for item in aws("resourcegroupstaggingapi", "get-resources", "--tag-filters", f"Key=Workshop,Values={prefix}")["ResourceTagMappingList"]:
        arn = item["ResourceARN"]
        kind, _, identifier = arn.rsplit(":", 1)[1].partition("/")
        if ":ec2:" in arn and kind in ec2_types:
            operation, flag = ec2_types[kind]
            result = subprocess.run(["aws", "ec2", operation, flag, identifier, "--profile", profile, "--region", manifest["region"], "--output", "json"], capture_output=True, text=True)
            if result.returncode and (".NotFound" in result.stderr or "InvalidVpcEndpointId.NotFound" in result.stderr):
                stale.append(arn)
                continue
            if result.returncode:
                raise RuntimeError(result.stderr)
        active.append(arn)
    check("active_tagged_resources", active)
    for stage in (ROOT / "infra").iterdir():
        path = stage / "terraform.tfstate"
        if path.exists():
            state = json.loads(path.read_text())
            check("state/" + stage.name, [r["type"] + "." + r["name"] for r in state.get("resources", []) if r["mode"] == "managed" and r.get("instances")])
    path = ROOT / ".local" / f"verification-{prefix}.json"
    path.write_text(json.dumps({"checks": report, "stale_tags_confirmed_not_found": stale}, indent=2, default=str))
    if any(report.values()):
        raise RuntimeError(f"Quedan recursos o eliminaciones asíncronas pendientes: {path}")
    print(f"PASS: no quedan recursos del inventario. Referencias de tags obsoletas: {len(stale)}. Informe: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--profile", default="workshop")
    args = parser.parse_args()
    try:
        verify(json.loads(args.manifest.read_text()), args.profile)
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
