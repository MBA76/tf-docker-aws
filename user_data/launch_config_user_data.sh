#!/bin/bash
sudo yum install -y aws-cli

aws s3 cp s3://jugnuu-ecs-config/ecs.config /etc/ecs/ecs.config
echo ECS_CLUSTER=ecs-jugnuu-cluster >> /etc/ecs/ecs.config
