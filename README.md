# tf-docker-aws
Run docker on AWS using Terraform

## Description

This terraform plan can be used to deploy a docker image on AWS Elastic Container Service. The EC2 instances are deployed within the default VPC. This plan uses the following resources on AWS:

- Elastic Container Service (ECS) Cluster
- ECS Task and Service
- Launch Configuration
- Auto Scaling Group
- Classic Load Balancer
- Default VPC and subnets
- Security Group
- AWS IAM Roles and Policies

This is a basic configuration which access the image using HTTP. This plan will be revised to allow choosing HTTPS and RDS as options during deployment.

## Usage

1. Run the following command to populate vars.tf file:
`cp vars.tf.sample vars.tf`

2. Setup your AWS CLI as described [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html).

```
$ aws configure --profile user2
AWS Access Key ID [None]: AKIAI44QH8DHBEXAMPLE
AWS Secret Access Key [None]: je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY
Default region name [None]: us-east-1
Default output format [None]: text
```

The profile name will be required when running terraform commands, and is referenced as `aws_profile` inside vars.tf.

3. Run `terraform init` to initialize a working directory containing Terraform configuration files.

4. This step is only needed when using private docker images that require authentication

  - Create a S3 bucket. In this example, I call the bucket `jugnuu-ecs-config`. Inside this bucket, store a file called `ecs.config` with the following values:

  ```
    ECS_ENGINE_AUTH_TYPE=docker
    ECS_ENGINE_AUTH_DATA={"https://index.docker.io/v1/":{"username":"<insert docker username>","password":"<insert docker password>","email":"<insert docker email>"}}
  ```

5. Modify the contents of `user_data/launch_config_user_data.sh` inside this repository using the following instructions:

  a. If you're using a private docker image as mentioned in step 4, replace the contents of user_data/launch_config_user_data.sh with the contents below. Don't forget to add the value for your ECS cluster name under `ECS_CLUSTER=<insert ECS cluster name here>`. It should be the same as the value specified inside vars.tf under `ecs_cluster_name`.


```
      #!/bin/bash
      sudo yum install -y aws-cli

      aws s3 cp s3://jugnuu-ecs-config/ecs.config /etc/ecs/ecs.config
      echo ECS_CLUSTER=<insert ECS cluster name here> >> /etc/ecs/ecs.config
```

  b. If you're using a public docker image, and you skipped step 4, replace the contents with the following:

```
      #!/bin/bash

      echo ECS_CLUSTER=<insert ECS cluster name here> >> /etc/ecs/ecs.config
```

  Save the file after you're done modifying.

6. Now run `terraform plan` and check if the output looks alright. You will be prompted to enter the values for variables inside vars.tf where no `default` is set. Feel free to set a `default` value where needed.

7. Run `terraform apply`. Look out for `elb_name` in your output. This should be the endpoint that can be used to access your newly deployed docker image.
