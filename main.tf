provider "aws" {
  region = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

resource "aws_ecs_cluster" "ecs-jugnuu" {
  name = "ecs-jugnuu-cluster"
}

# use default VPC
resource "aws_default_vpc" "default" {
  tags {
    Name = "Default VPC"
  }
}

data "aws_subnet_ids" "default-subnet-ids" {
  vpc_id = "${aws_default_vpc.default.id}"
}

# Security group configuration
resource "aws_security_group" "ecs-jugnuu-security-group" {
  name = "ecs-jugnuu-security-group"
  description = "Security group for deploying instances"
  vpc_id = "${aws_default_vpc.default.id}"

  ingress {
    from_port = "22"
    to_port = "22"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "ecs-jugnuu-security-group"
  }
}

# Declare the data source
data "aws_availability_zones" "available" {}

# Load balancer config
resource "aws_elb" "ecs-jugnuu-load-balancer" {
  name               = "ecs-jugnuu-load-balancer"
  availability_zones = ["${data.aws_availability_zones.available.names}"]
  security_groups = ["${aws_security_group.ecs-jugnuu-security-group.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  tags {
    Name = "ecs-jugnuu-load-balancer"
  }
}
