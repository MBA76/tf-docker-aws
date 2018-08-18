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

resource "aws_ecs_cluster" "ecs-cluster" {
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
resource "aws_security_group" "ecs-security-group" {
  name = "ecs-${var.application_name}-security-group"
  description = "Security group for deploying instances"
  vpc_id = "${aws_default_vpc.default.id}"

  ingress {
    from_port = "22"
    to_port = "22"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = "80"
    to_port = "80"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = "0"
    to_port = "0"
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "ecs-${var.application_name}-security-group"
  }
}

# Declare the data source
data "aws_availability_zones" "available" {}

# Load balancer config
resource "aws_elb" "ecs-load-balancer" {
  name               = "ecs-${var.application_name}-load-balancer"
  availability_zones = ["${data.aws_availability_zones.available.names}"]
  security_groups = ["${aws_security_group.ecs-security-group.id}"]

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

  idle_timeout                = 300
  connection_draining         = true
  connection_draining_timeout = 300

  tags {
    Name = "ecs-${var.application_name}-load-balancer"
  }
}

# Create AWS instance role to allow EC2 instances to communicate with ECS
resource "aws_iam_role" "ecs-instance-role" {
  name = "ecs_instance_role"
  description = "Allows EC2 instances to communicate with ECS and read from S3"
  assume_role_policy = "${file("role_policies/policy.json")}"
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
  assume_role_policy  = "${data.aws_iam_policy_document.ecs-service-policy.json}"
}

data "aws_iam_policy_document" "ecs-service-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
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
  name_prefix   = "${var.application_name}_launch_config"
  image_id      = "${data.aws_ami.linux-ecs-optimized.id}"
  instance_type = "t2.micro"
  security_groups = ["${aws_security_group.ecs-security-group.id}"]
  key_name = "${var.key_name}"
  iam_instance_profile = "${aws_iam_instance_profile.ec2-instance-profile.name}"

  # Add Storage
  root_block_device {
    volume_type                 = "gp2"
    volume_size                 = 8
    iops                        = 100
    delete_on_termination       = "true"
  }

  ebs_block_device {
    device_name                 = "/dev/xvdcz"
    volume_type                 = "gp2"
    volume_size                 = 22
    iops                        = 100
  }

  lifecycle {
    create_before_destroy = true
  }
  user_data = "${file("user_data/launch_config_user_data.sh")}"
}

resource "aws_autoscaling_group" "aws-auto-scaling-group" {
  name                 = "${var.application_name}-asg"
  launch_configuration = "${aws_launch_configuration.aws-launch-config.name}"
  vpc_zone_identifier  = ["${data.aws_subnet_ids.default-subnet-ids.ids}"]
  min_size             = "${var.asg_configuration["min_instances"]}"
  max_size             = "${var.asg_configuration["max_instances"]}"

  lifecycle {
    create_before_destroy = true
  }
}

# Add ECS task and container definitions
resource "aws_ecs_task_definition" "ecs-task" {
  family                = "${var.application_name}-ecs-task"
  container_definitions = "${file("task_definitions/service.json")}"
  requires_compatibilities = ["EC2"]
}

# Add ECS service
resource "aws_ecs_service" "ecs-service" {
  name            = "${var.application_name}-ecs-service"
  cluster         = "${aws_ecs_cluster.ecs-cluster.id}"
  task_definition = "${aws_ecs_task_definition.ecs-task.arn}"
  desired_count   = "${var.ecs_configuration["number_tasks"]}"
  iam_role        = "${aws_iam_role.ecs-service-role.arn}"
  depends_on      = ["aws_iam_role.ecs-service-role"]

  load_balancer {
    elb_name = "${aws_elb.ecs-load-balancer.name}"
    container_name   = "${var.application_name}"
    container_port   = 3000
  }
}

output "elb_name" {
  value = "${aws_elb.ecs-load-balancer.name}"
}
