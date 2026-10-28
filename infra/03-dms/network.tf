resource "aws_security_group" "dms" {
  name_prefix = "${var.workshop_name}-dms-"
  description = "Private DMS replication instance"
  vpc_id      = local.aurora.vpc_id
}

resource "aws_security_group" "services" {
  name_prefix = "${var.workshop_name}-services-"
  description = "HTTPS from the workshop replication instance"
  vpc_id      = local.aurora.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_dms" {
  security_group_id            = local.aurora.aurora_security_group_id
  referenced_security_group_id = aws_security_group.dms.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "dms_to_aurora" {
  security_group_id            = aws_security_group.dms.id
  referenced_security_group_id = local.aurora.aurora_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "services_from_dms" {
  security_group_id            = aws_security_group.services.id
  referenced_security_group_id = aws_security_group.dms.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "dms_to_services" {
  security_group_id            = aws_security_group.dms.id
  referenced_security_group_id = aws_security_group.services.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.aurora.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [local.aurora.private_route_table_id]
}

resource "aws_vpc_security_group_egress_rule" "dms_to_s3" {
  security_group_id = aws_security_group.dms.id
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "services" {
  for_each            = toset(["secretsmanager", "glue", "athena", "logs"])
  vpc_id              = local.aurora.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  # Single-AZ endpoints keep this short-lived workshop smaller; not an HA design.
  subnet_ids         = [local.aurora.private_subnet_ids[0]]
  security_group_ids = [aws_security_group.services.id]
}

resource "aws_dms_replication_subnet_group" "workshop" {
  replication_subnet_group_id          = "${var.workshop_name}-dms"
  replication_subnet_group_description = "Workshop private subnets"
  subnet_ids                           = local.aurora.private_subnet_ids
}
