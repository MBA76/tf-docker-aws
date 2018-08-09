# terraform {
#   backend "s3" {
#     bucket = "my-bucket-name"
#     key = "filename.tfstate"
#     region = "eu-west-2"
#     encrypt = true
#   }
# }

provider "aws" {
  region = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

resource "aws_ecs_cluster" "ecs-jugnuu" {
  name = "${var.ecs_cluster_name}"
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

# Create AWS instance role to allow EC2 instances to communicate with ECS
resource "aws_iam_role" "ecs-instance-role" {
  name = "ecs_instance_role"
  description = "Allows EC2 instances to communicate with ECS and read from S3"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ec2-instance-profile" {
  name = "ec2-instance-profile"
  role = "${aws_iam_role.ecs-instance-role.name}"
}

resource "aws_iam_role_policy_attachment" "ecs-instance-policy-1" {
  role       = "${aws_iam_role.ecs-instance-role.name}"
  policy_arn = "${var.aws_s3_read_policy_arn}"
}

resource "aws_iam_role_policy_attachment" "ecs-instance-policy-2" {
  role       = "${aws_iam_role.ecs-instance-role.name}"
  policy_arn = "${var.aws_ec2_instance_policy_arn}"
}

# Create AWS ECS service role ro allow ECS cluster to communicate with ELB
resource "aws_iam_role" "ecs-service-role" {
  name = "ecs_service_role"
  description = "Allows ECS cluster to communicate with ELB"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs-service-policy-1" {
  role       = "${aws_iam_role.ecs-service-role.name}"
  policy_arn = "${var.aws_ec2_service_policy_arn}"
}


# Create auto-scaling group
data "aws_ami" "linux-ecs-optimized" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami-2018.03.a-amazon-ecs-optimized"]
  }

  owners = ["591542846629"] # Canonical
}

resource "aws_launch_configuration" "aws-launch-config" {
  name_prefix   = "jugnuu_launch_config"
  image_id      = "${data.aws_ami.linux-ecs-optimized.id}"
  instance_type = "t2.micro"
  security_groups = ["${aws_security_group.ecs-jugnuu-security-group.id}"]
  key_name = "${var.key_name}"
  iam_instance_profile = "${aws_iam_instance_profile.ec2-instance-profile.name}"

  lifecycle {
    create_before_destroy = true
  }
  user_data = <<EOF
#!/bin/bash
yum install -y aws-cli
aws s3 cp s3://jugnuu-ecs-config/ecs.config /etc/ecs/ecs.config
EOF
}

resource "aws_autoscaling_group" "aws-auto-scaling-group" {
  name                 = "jugnuu-asg"
  launch_configuration = "${aws_launch_configuration.aws-launch-config.name}"
  vpc_zone_identifier  = ["${data.aws_subnet_ids.default-subnet-ids.ids}"]
  min_size             = 2
  max_size             = 2

  lifecycle {
    create_before_destroy = true
  }
}


# Add ECS task and container definitions
resource "aws_ecs_task_definition" "jugnuu-ecs-task" {
  family                = "jugnuu-web-ecs-task"
  container_definitions = "${file("task-definitions/service.json")}"
}

# Add ECS service
resource "aws_ecs_service" "jugnuu-ecs-service" {
  name            = "jugnuu-ecs-service"
  cluster         = "${aws_ecs_cluster.ecs-jugnuu.id}"
  task_definition = "${aws_ecs_task_definition.jugnuu-ecs-task.arn}"
  desired_count   = 1
  iam_role        = "${aws_iam_role.ecs-service-role.arn}"
  depends_on      = ["aws_iam_role.ecs-service-role"]

  load_balancer {
    elb_name = "${aws_elb.ecs-jugnuu-load-balancer.name}"
    container_name   = "jugnuu-web"
    container_port   = 3000
  }
}
