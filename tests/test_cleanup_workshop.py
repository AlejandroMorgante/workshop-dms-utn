import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location("cleanup", Path(__file__).parents[1] / "scripts/cleanup_workshop.py")
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class CleanupTests(unittest.TestCase):
    def test_reject_foreign_bucket_and_task(self):
        base = {"account": "123456789012", "workshop": "utn-demo", "region": "us-east-1", "buckets": [], "tasks": []}
        for key, value in [("buckets", ["another-bucket"]), ("tasks", ["arn:aws:dms:us-east-1:999999999999:task:EXAMPLE"])]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                cleanup.validate_manifest({**base, key: value}, "123456789012", "utn-demo")

    def test_reject_foreign_resource_even_with_matching_manifest_account(self):
        manifest = {"account": "123456789012", "workshop": "utn-demo", "region": "us-east-1", "buckets": [], "tasks": [], "resources": [{"arn": "arn:aws:rds:us-east-1:999999999999:cluster:utn-demo-aurora"}]}
        with self.assertRaises(ValueError):
            cleanup.validate_manifest(manifest, "123456789012", "utn-demo")

    def test_reject_foreign_state_tags(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp) / "infra/01-aurora"
            directory.mkdir(parents=True)
            (directory / "terraform.tfstate").write_text(json.dumps({"resources": [{"mode": "managed", "type": "aws_vpc", "name": "workshop", "instances": [{"attributes": {"tags_all": {"Project": "another-project", "Workshop": "utn-demo"}}}]}]}))
            with self.assertRaises(ValueError):
                cleanup.inventory(Path(tmp), "123456789012", "utn-demo")

    def test_inventory_preserves_service_specific_arn(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp) / "infra/03-dms"
            directory.mkdir(parents=True)
            arn = "arn:aws:dms:us-east-1:123456789012:endpoint:EXAMPLE"
            (directory / "terraform.tfstate").write_text(json.dumps({"resources": [{"mode": "managed", "type": "aws_dms_s3_endpoint", "name": "target", "instances": [{"attributes": {"id": "utn-demo-target", "endpoint_arn": arn}}]}]}))
            result = cleanup.inventory(Path(tmp), "123456789012", "utn-demo")
            self.assertEqual(result["resources"][0]["arn"], arn)

    def test_delete_exact_versions_and_markers(self):
        s3 = Mock()
        s3.get_bucket_tagging.return_value = {"TagSet": [{"Key": "Workshop", "Value": "utn-demo"}, {"Key": "Project", "Value": "workshop-dms-utn"}]}
        versions = Mock()
        versions.paginate.return_value = [{"Versions": [{"Key": "data", "VersionId": "v1"}], "DeleteMarkers": [{"Key": "data", "VersionId": "v2"}]}]
        uploads = Mock()
        uploads.paginate.return_value = []
        s3.get_paginator.side_effect = [versions, uploads]
        s3.delete_objects.return_value = {}
        cleanup.empty_bucket(s3, "bucket", "123456789012", "utn-demo")
        self.assertEqual(s3.delete_objects.call_args.kwargs["Delete"]["Objects"], [{"Key": "data", "VersionId": "v1"}, {"Key": "data", "VersionId": "v2"}])
        self.assertEqual(s3.delete_objects.call_args.kwargs["ExpectedBucketOwner"], "123456789012")

    def test_refuse_bucket_with_wrong_live_tags(self):
        s3 = Mock()
        s3.get_bucket_tagging.return_value = {"TagSet": []}
        with self.assertRaises(ValueError):
            cleanup.empty_bucket(s3, "bucket", "123456789012", "utn-demo")
        s3.delete_objects.assert_not_called()


if __name__ == "__main__":
    unittest.main()
