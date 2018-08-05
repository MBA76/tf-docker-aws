# resource "aws_lb" "ecs-jugnuu-load-balancer" {
#   name               = "ecs-jugnuu-load-balancer"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = ["${aws_security_group.ecs-jugnuu-security-group.id}"]
#   subnets            = ["${data.aws_subnet_ids.default-subnet-ids.ids}"]

#   enable_deletion_protection = false

#   tags {
#     name = "ecs-jugnuu-load-balancer"
#   }
# }

# resource "aws_lb_target_group" "ecs-jugnuu-lb-target-group" {
#   name     = "ecs-jugnuu-lb-target-group"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = "${aws_default_vpc.default.id}"
# }

# resource "aws_lb_listener" "ecs-jugnuu-lb-listener" {
#   load_balancer_arn = "${aws_lb.ecs-jugnuu-load-balancer.arn}"
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     target_group_arn = "${aws_lb_target_group.ecs-jugnuu-lb-target-group.arn}"
#     type             = "forward"
#   }
# }
