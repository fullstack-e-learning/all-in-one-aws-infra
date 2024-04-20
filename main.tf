locals {
  instance_count = 2
  tags = {
    Name = "all-in-one-lb"
  }
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

  tags = local.tags
}

#NETWORK INTERFACE
resource "aws_network_interface" "foo" {
  count     = length(var.availability_zones)
  subnet_id = count.index == 0 ? data.aws_subnet.az-1a.id : data.aws_subnet.az-1b.id

  security_groups = [aws_security_group.ec2.id]
  tags            = local.tags
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

  tags = local.tags
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

  tags = local.tags
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

  tags = local.tags
}

resource "aws_efs_mount_target" "az-1a" {
  file_system_id  = aws_efs_file_system.foo.id
  subnet_id       = data.aws_subnet.az-1a.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "az-1b" {
  file_system_id  = aws_efs_file_system.foo.id
  subnet_id       = data.aws_subnet.az-1b.id
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

# Postgres DB
resource "aws_db_instance" "postgresdb" {
  identifier           = "allinone-postgres-db"
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "16.2"
  instance_class       = "db.t3.micro"
  username             = "postgres"
  password             = random_password.postgres_password.result
  publicly_accessible  = true
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
}

resource "random_password" "postgres_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = [data.aws_subnet.az-1a.id, data.aws_subnet.az-1b.id]
  tags       = local.tags
}

output "endpoint" {
  value = aws_db_instance.postgresdb.endpoint
}

# ALB
resource "aws_lb" "alb" {
  name               = "allinone-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2.id]
  subnets            = [data.aws_subnet.az-1a.id, data.aws_subnet.az-1b.id]

  tags = local.tags
}

resource "aws_lb_target_group" "alb-tg" {
  name        = "allinone-tg"
  target_type = "instance"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.vpc.id

  health_check {
    path                = "/index.html"
    protocol            = "HTTP"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "listener_80" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-tg.arn
  }
}

resource "aws_lb_target_group_attachment" "my_instance_attachment" {
  count            = local.instance_count
  target_group_arn = aws_lb_target_group.alb-tg.arn
  target_id        = aws_instance.foo.*.id[count.index]
  port             = 80
}

resource "ansible_host" "host" {
  count = local.instance_count
  name  = aws_instance.foo[count.index].public_ip

  groups = ["ec2"]
  variables = {
    ansible_user                 = "ubuntu"
    ansible_ssh_private_key_file = "id_rsa.pem"
    ansible_connection           = "ssh"
    ansible_ssh_common_args      = "-o StrictHostKeyChecking=no"
    mount_path                   = "/home/ubuntu/efs"
    efs_endpoint                 = "${aws_efs_file_system.foo.dns_name}:/"
    db_host                      = aws_db_instance.postgresdb.address
    db_port                      = aws_db_instance.postgresdb.port
    db_name                      = aws_db_instance.postgresdb.db_name
    db_username                  = aws_db_instance.postgresdb.username
    db_password                  = random_password.postgres_password.result
  }
}
