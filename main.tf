locals {
  instance_count = 2
}

variable "availability_zones" {
  type    = list(string)
  default = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
}


#VPC
data "aws_vpc" "vpc" {

}

# SUBNET
data "aws_subnet" "az-1a" {
  availability_zone = "eu-north-1a"
}
data "aws_subnet" "az-1b" {
  availability_zone = "eu-north-1b"
}

#SECURITY GROUP
resource "aws_security_group" "ec2" {
  name        = "ec2-sg"
  description = "Allow SSH and Http inbound traffic"
  vpc_id      = data.aws_vpc.vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "all-in-one-infra"
  }
}

#NETWORK INTERFACE
resource "aws_network_interface" "foo" {
  count     = length(var.availability_zones)
  subnet_id = count.index == 0 ? data.aws_subnet.az-1a.id : data.aws_subnet.az-1b.id

  security_groups = [aws_security_group.ec2.id]
  tags = {
    Name = "all-in-one-infra"
  }
}

resource "tls_private_key" "foo" {
  algorithm = "RSA"
  rsa_bits  = 2048
}


#ssh-keygen -t rsa -b 4096 -f ./keypair/id_rsa
resource "aws_key_pair" "foo" {
  key_name   = "id_rsa"
  public_key = tls_private_key.foo.public_key_openssh
}

#EC2
resource "aws_instance" "foo" {
  count         = local.instance_count
  ami           = "ami-0014ce3e52359afbd"
  instance_type = "t3.micro"

  availability_zone = element(var.availability_zones, count.index)

  network_interface {
    network_interface_id = aws_network_interface.foo[count.index].id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  key_name = aws_key_pair.foo.key_name

  tags = {
    Name = "all-in-one-infra"
  }
}

# EFS
resource "aws_efs_file_system" "foo" {
  creation_token   = "efs-ec2-lb-example"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "all-in-one-infra"
  }
}

resource "aws_security_group" "efs" {
  name        = "efs-sg"
  description = "Allow ec2-sg will talk to this efs"
  vpc_id      = data.aws_vpc.vpc.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # ec2-sg
    security_groups = [aws_security_group.ec2.id]
  }

  tags = {
    Name = "all-in-one-infra"
  }
}

resource "aws_efs_mount_target" "foo" {
  file_system_id  = aws_efs_file_system.foo.id
  subnet_id       = data.aws_subnet.az-1a.id
  security_groups = [aws_security_group.efs.id]
}


output "ec2_host_public_ip" {
  value = aws_instance.foo[*].public_ip
}

output "efs_hostname" {
  value = aws_efs_file_system.foo.dns_name
}

output "tls_private_key" {
  value     = tls_private_key.foo.private_key_pem
  sensitive = true
}

resource "ansible_host" "host" {
  count  = local.instance_count
  name   = aws_instance.foo[count.index].public_ip
  groups = ["ec2"]
  variables = {
    ansible_user                 = "ubuntu"
    ansible_ssh_private_key_file = "id_rsa.pem"
    ansible_connection           = "ssh"
    ansible_ssh_common_args      = "-o StrictHostKeyChecking=no"
    mount_path                   = "/home/ubuntu/efs"
    efs_endpoint                 = "${aws_efs_file_system.foo.dns_name}:/"
  }
}

resource "aws_db_instance" "postgresdb" {
  identifier          = "allinone-postgres-db"
  allocated_storage   = 20
  engine              = "postgres"
  engine_version      = "16.2"
  instance_class      = "db.t3.micro"
  username            = "postgres"
  password            = random_password.postgres_password.result
  publicly_accessible = true
  skip_final_snapshot = true
}

resource "random_password" "postgres_password" {
  length           = 16
  special          = true
  override_special = "/@%^"
}

output "endpoint" {
  value = aws_db_instance.postgresdb.endpoint
}

resource "aws_elb" "lb" {
  name               = "allinone-lb"
  availability_zones = ["eu-north-1a", "eu-north-1b"]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                   = [aws_instance.foo[0].id, aws_instance.foo[1].id]
  cross_zone_load_balancing   = true
  idle_timeout                = 40
  
  tags = {
    Name = "all-in-one-lb"
  }
}