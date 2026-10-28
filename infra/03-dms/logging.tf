# DMS chooses this group name from the replication instance identifier.
# It belongs to the shared instance, not to an individual full-load/CDC task.
resource "aws_cloudwatch_log_group" "tasks" {
  name              = "dms-tasks-${aws_dms_replication_instance.workshop.replication_instance_id}"
  retention_in_days = 7
}
