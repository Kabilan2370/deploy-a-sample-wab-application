resource "aws_vpc" "one" {
  cidr_block       = var.cidr_block
  instance_tenancy = "default"
  enable_dns_hostnames = var.host_name

  tags = {
    Name = "TOT-vpc"
  }
}
resource "aws_subnet" "sub1" {
  vpc_id     = aws_vpc.one.id
  cidr_block = "10.0.1.0/24"
  availability_zone       = "us-east-1e"

  tags = {
    Name = "sub-one"
  }
}

resource "aws_subnet" "sub2" {
  vpc_id     = aws_vpc.one.id
  cidr_block = "10.0.2.0/24"
  availability_zone       = "us-east-1f"

  tags = {
    Name = "sub-two"
  }
}

# IG
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.one.id

  tags = {
    Name = "Gateway"
  }
}

# Route table
resource "aws_route_table" "route1" {
  vpc_id = aws_vpc.one.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "route-table-one"
  }
}
# Association 
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.route1.id
}

resource "aws_route_table" "route2" {
  vpc_id = aws_vpc.one.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "route-table-two"
  }
}
# Association 
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.sub2.id
  route_table_id = aws_route_table.route2.id
}

# security group
resource "aws_security_group" "public_sg" {
  name        = "public-sg"
  description = "Allow web and ssh traffic"
  vpc_id      = aws_vpc.one.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

  }
}

# iam role
resource "aws_iam_role_policy" "test_policy" {
  name = "test_policy"
  role = aws_iam_role.test_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
          "s3:*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "test_role" {
  name = "s3-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

# code deploy role

resource "aws_iam_role_policy_attachment" "codedeploy_attach" {
  role       = aws_iam_role.codedeploy_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

resource "aws_iam_role" "codedeploy_service" {
  name = "codedeploy-service-role"
  
   assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      },
    ]
  })
}
  

# instance profile

resource "aws_iam_instance_profile" "test_profile" {
  name = "test_profile"
  role = aws_iam_role.test_role.name
}

# s3 bucker
resource "aws_s3_bucket" "example" {
  bucket = "bit-bucket-online"
#   versioning_configuration {
#     status = "Disabled"
#   }

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

resource "aws_instance" "master" {
  ami                           = var.ami_id
  instance_type                 = var.inst_type
  subnet_id                     = aws_subnet.sub1.id
  key_name                      = var.key
  associate_public_ip_address   = var.public_key
  security_groups               = [aws_security_group.public_sg.id]
  user_data                   = <<-EOF
                            #!/bin/bash
                            apt update -y
                            snap install aws-cli --classic
                            EOF
  tags = {
    name = "Devloper"
}

}

resource "aws_instance" "slave" {
  ami                           = var.ami_id
  instance_type                 = var.inst_type
  subnet_id                     = aws_subnet.sub2.id
  key_name                      = var.key
  associate_public_ip_address   = var.public_key
  security_groups               = [aws_security_group.public_sg.id]
  iam_instance_profile      = aws_iam_instance_profile.test_profile.id
  user_data                   = <<-EOF
                              #!/bin/bash
                              apt update -y
                              apt install ruby-full -y
                              apt install wget -y
                              cd /home/ubuntu
                              https://aws-codedeploy-us-east-2.s3..amazonaws.com/latest/install
                              chmod +x ./install
                              EOF
  tags = {
    name = "Code-deployment"
}
}

# Code deploy
resource "aws_codedeploy_app" "app" {
  compute_platform = "Server"
  name             = "example"
}

resource "aws_codedeploy_deployment_config" "foo" {
  deployment_config_name = "test-deployment-config"

  minimum_healthy_hosts {
    type  = "HOST_COUNT"
    value = 2
  }
}

resource "aws_codedeploy_deployment_group" "foo2" {
  app_name               = aws_codedeploy_app.app.name
  deployment_group_name  = "bar"
  service_role_arn       = aws_iam_role.codedeploy_service.arn
  deployment_config_name = aws_codedeploy_deployment_config.foo.id

  ec2_tag_filter {
    key   = "name"
    type  = "KEY_AND_VALUE"
    value = "aws_instance.slave.name"
  }

  

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

 
}