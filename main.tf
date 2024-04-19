locals {
  instance_count = 2
  tags = {
    Name = "all-in-one-lb"
  }
}

#VPC
data "aws_vpc" "vpc" {}

# SUBNET
data "aws_subnet" "az1a" {
  availability_zone = "eu-north-1a"
}
data "aws_subnet" "az1b" {
  availability_zone = "eu-north-1b"
}

resource "aws_db_subnet_group" "foo" {
  name       = "db-subnet-groups"
  subnet_ids = [data.aws_subnet.az1a.id, data.aws_subnet.az1b.id]
  tags       = local.tags
}

# INTERNET GATEWAY (default)

# ROUTE TABLE (default)

# ROUTE TABLE (default)


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
  count = local.instance_count

  subnet_id       = data.aws_subnet.az1a.id
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
  count = local.instance_count

  ami           = "ami-0014ce3e52359afbd"
  instance_type = "t3.micro"

  network_interface {
    network_interface_id = aws_network_interface.foo[count.index].id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  key_name = aws_key_pair.foo.key_name
  tags     = local.tags
}

# EFS
resource "aws_efs_file_system" "foo" {
  creation_token   = "all-in-one-example"
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

resource "aws_efs_mount_target" "foo" {
  file_system_id  = aws_efs_file_system.foo.id
  subnet_id       = data.aws_subnet.az1a.id
  security_groups = [aws_security_group.efs.id]
}

# Db

resource "aws_security_group" "db" {
  name        = "db-sg"
  description = "Allow ec2-sg will talk to this db"
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

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_instance" "db" {
  allocated_storage      = 10
  db_name                = "postgres"
  engine                 = "postgres"
  engine_version         = "16.2"
  instance_class         = "db.t3.micro"
  username               = "postgres"
  password               = random_password.password.result
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.foo.name
  vpc_security_group_ids = [aws_security_group.db.id]

  tags = local.tags
}


# Load Balancer
resource "aws_security_group" "lb-sg" {
  name        = "lb-sg"
  description = "Allow http inbound traffic"
  vpc_id      = data.aws_vpc.vpc.id

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
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = local.tags
}

resource "aws_lb_target_group" "foo" {
  name     = "all-in-one-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.vpc.id
  health_check {
    enabled  = true
    port     = "traffic-port"
    path     = "/actuator/health"
    protocol = "HTTP"
  }
  
  tags = local.tags
}

resource "aws_lb_target_group_attachment" "foo" {
  count            = local.instance_count

  target_group_arn = aws_lb_target_group.foo.arn
  target_id        = aws_instance.foo[count.index].id
  port             = 80
}

resource "aws_lb" "foo" {
  name               = "all-in-one-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb-sg.id]
  subnets            = [data.aws_subnet.az1a.id, data.aws_subnet.az1b.id]

  enable_deletion_protection = false

  # access_logs {
  #   bucket  = aws_s3_bucket.lb_logs.id
  #   prefix  = "test-lb"
  #   enabled = true
  # }

  tags = local.tags
}

resource "aws_lb_listener" "foo" {
  load_balancer_arn = aws_lb.foo.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.foo.arn
  }

  tags = local.tags
}


# Output
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

output "db_endpoint" {
  value = aws_db_instance.db.endpoint
}

output "lb_fqdn" {
  value = aws_lb.foo.dns_name
}

# ansible
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
    db_endpoint                  = aws_db_instance.db.endpoint
    db_name                      = aws_db_instance.db.db_name
    db_username                  = aws_db_instance.db.username
    db_password                  = aws_db_instance.db.password
  }
}
