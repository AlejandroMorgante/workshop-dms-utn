data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

resource "aws_vpc" "workshop" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.workshop_name }
}

# Aurora needs a subnet group spanning at least two Availability Zones.
# Data API reaches the private database without a NAT gateway or a bastion.
resource "aws_subnet" "private" {
  count = 2

  vpc_id                  = aws_vpc.workshop.id
  cidr_block              = cidrsubnet(aws_vpc.workshop.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.workshop_name}-private-${count.index + 1}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.workshop.id
  tags   = { Name = "${var.workshop_name}-private" }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "aurora" {
  name_prefix = "${var.workshop_name}-aurora-"
  description = "Private Aurora; Data API access only in stage 01"
  vpc_id      = aws_vpc.workshop.id
  ingress     = []
  egress      = []

  tags = { Name = "${var.workshop_name}-aurora" }
}
