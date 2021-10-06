terraform {
  required_providers {
      aws = {
          source = "hashicorp/aws"
          version = "~> 3.27"
      }
  }

  required_version = ">= 0.14.9"
}


##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
    profile = "default"
    region = var.region
}

##################################################################################
# DATA
##################################################################################

data "aws_availability_zones" "available" {}

data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "task-vpc"

  cidr            = "10.0.0.0/16"
  azs             = data.aws_availability_zones.available.names
  public_subnets  = ["10.0.0.0/24"]
  private_subnets = ["10.0.1.0/24"]
  database_subnets = [ "10.0.2.0/24", "10.0.3.0/24", "10.0.4.0/24" ]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  create_database_subnet_group = true
  create_database_subnet_route_table = true

  #enable_dns_hostnames = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

# DATABASE #
resource "aws_security_group" "rds" {
  name = "tasks_rds"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    cidr_blocks = module.vpc.public_subnets_cidr_blocks #CHANGE BACK TO PRIVATE
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  tags = {
    Name = "tasksdb_security_group"
  }
}

resource "aws_db_parameter_group" "tasksdb" {
  name   = "tasksdb"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8"
  }
}

resource "aws_db_instance" "tasksdb" {
  identifier = "tasksdb"
  instance_class = "db.t2.micro"
  allocated_storage = 20
  engine = "mysql"
  engine_version = "8.0.23"
  username = "tasks"
  password = var.db_password
  db_subnet_group_name = module.vpc.database_subnet_group
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name = aws_db_parameter_group.tasksdb.name
  publicly_accessible = false
  skip_final_snapshot = true
  name = "tasksAPI"
}
# end of database #

# webapp #
resource "aws_security_group" "private" {
  name = "task-webapp-sg"
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}

resource "aws_instance" "webapp_instance" {
  ami = data.aws_ami.aws-linux.id
  instance_type = "t2.micro"
  iam_instance_profile = "EC2-S3-Read-Access"

  subnet_id = module.vpc.private_subnets[0]
  vpc_security_group_ids = [ aws_security_group.private.id ]
  key_name = "dom"

  user_data = <<-EOF
  #! /bin/bash
  sudo yum update -y
  sudo yum install java -y
  export DB_IP=${aws_db_instance.tasksdb.address}
  export DB_PORT=${aws_db_instance.tasksdb.port}
  export DB_USERNAME=${aws_db_instance.tasksdb.username}
  export DB_PASSWORD=${var.db_password}
  aws s3 cp s3://task-web-dev-bucket/tasks-webapp.jar ./
  nohup java -jar tasks-webapp.jar &
  EOF

  tags = {
    Name = "webapp-instance"
    Terraform = "true"
  }
}
# end of webapp #

# static website #
resource "aws_security_group" "public" {
  name = "task-web-sg"
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}