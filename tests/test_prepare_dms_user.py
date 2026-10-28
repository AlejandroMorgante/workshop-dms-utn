import importlib.util
import json
import unittest
from pathlib import Path
from unittest.mock import Mock

SPEC = importlib.util.spec_from_file_location("helper", Path(__file__).parents[1] / "scripts/prepare_dms_user.py")
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.config = dict(account_id="123456789012", region="us-east-1", username="dms_reader", database="workshop",
                           host="test.cluster-example.us-east-1.rds.amazonaws.com",
                           resource_arn="arn:aws:rds:us-east-1:123456789012:cluster:utn",
                           admin_secret_arn="arn:aws:secretsmanager:us-east-1:123456789012:secret:admin",
                           source_secret_arn="arn:aws:secretsmanager:us-east-1:123456789012:secret:dms")
        self.sts, self.sm, self.data = Mock(), Mock(), Mock()
        self.sts.get_caller_identity.return_value = {"Account": "123456789012"}
        self.sm.describe_secret.return_value = {}
        self.data.begin_transaction.return_value = {"transactionId": "transaction"}

    def test_wrong_account_never_reads_or_writes_secret(self):
        self.sts.get_caller_identity.return_value = {"Account": "999999999999"}
        with self.assertRaises(ValueError): helper.prepare(self.config, self.sts, self.sm, self.data)
        self.sm.describe_secret.assert_not_called()
        self.data.begin_transaction.assert_not_called()

    def test_password_is_not_sent_to_sql(self):
        helper.prepare(self.config, self.sts, self.sm, self.data)
        secret = json.loads(self.sm.put_secret_value.call_args.kwargs["SecretString"])
        self.assertNotIn(secret["password"], str(self.data.mock_calls))
        self.assertIn("SCRAM-SHA-256", str(self.data.execute_statement.call_args_list[0]))
        self.data.commit_transaction.assert_called_once()

    def test_failed_sql_rolls_back_and_retry_reuses_secret(self):
        self.data.execute_statement.side_effect = RuntimeError("SQL failed")
        with self.assertRaises(RuntimeError): helper.prepare(self.config, self.sts, self.sm, self.data)
        self.data.rollback_transaction.assert_called_once()
        self.data.commit_transaction.assert_not_called()
        secret = self.sm.put_secret_value.call_args.kwargs["SecretString"]
        self.sm.describe_secret.return_value = {"VersionIdsToStages": {"version": ["AWSCURRENT"]}}
        self.sm.get_secret_value.return_value = {"SecretString": secret}
        self.data.execute_statement.side_effect = None
        helper.prepare(self.config, self.sts, self.sm, self.data)
        self.sm.put_secret_value.assert_called_once()  # Retry did not rotate the credential.
        self.data.commit_transaction.assert_called_once()

    def test_foreign_secret_is_not_overwritten(self):
        self.sm.describe_secret.return_value = {"VersionIdsToStages": {"version": ["AWSCURRENT"]}}
        self.sm.get_secret_value.return_value = {"SecretString": json.dumps({"username": "someone_else"})}
        with self.assertRaises(ValueError): helper.prepare(self.config, self.sts, self.sm, self.data)
        self.sm.put_secret_value.assert_not_called()
        self.data.begin_transaction.assert_not_called()


if __name__ == "__main__":
    unittest.main()
