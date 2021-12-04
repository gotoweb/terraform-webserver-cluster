terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "3.66.0"
    }
  }
}

provider "aws" {
  profile = "default"
  region = "ap-northeast-2"
}

resource "aws_vpc" "tutorial" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "terraform-tutorial-vpc"
  }
}

resource "aws_subnet" "public1" {
  vpc_id = aws_vpc.tutorial.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "terraform-tutorial-public1"
  }
}

resource "aws_subnet" "public2" {
  vpc_id = aws_vpc.tutorial.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "ap-northeast-2d"

  tags = {
    Name = "terraform-tutorial-public2"
  }
}

resource "aws_subnet" "private1" {
  vpc_id = aws_vpc.tutorial.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-northeast-2b"

  tags = {
    Name = "terraform-tutorial-private1"
  }
}

resource "aws_subnet" "private2" {
  vpc_id = aws_vpc.tutorial.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-northeast-2c"

  tags = {
    Name = "terraform-tutorial-private2"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.tutorial.id

  tags = {
    Name = "terraform-tutorial-ig"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.tutorial.id

  tags = {
    Name = "public-route"
  }
}


resource "aws_route" "r" {
  route_table_id            = aws_route_table.public.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id
  depends_on                = [aws_route_table.public]
}

resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_vpc.tutorial.default_route_table_id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_vpc.tutorial.default_route_table_id
}

resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}


resource "aws_security_group" "tutorial" {
  vpc_id = aws_vpc.tutorial.id
  tags = {
    Name = "terraform-tutorial-securitygroup"
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    # type = "ssh"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    # type = "http"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "tutorial_db" {
  vpc_id = aws_vpc.tutorial.id
  tags = {
    Name = "terraform-tutorial-db-securitygroup"
  }

  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    # type = "MYSQL/Aurora"
    security_groups = [ aws_security_group.tutorial.id ]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}


resource "aws_launch_configuration" "tutorial" {
  image_id        = "ami-0252a84eb1d66c2a0"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF

  associate_public_ip_address = true
  key_name = "hoyong"

  # Required when using a launch configuration with an auto scaling group.
  # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "tutorial" {
  launch_configuration = aws_launch_configuration.tutorial.name

  vpc_zone_identifier  = [ aws_subnet.public1.id ]

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 10

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "instance" {
  name = var.instance_security_group_name
  vpc_id      = aws_vpc.tutorial.id

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
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
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_lb" "tutorial" {

  name               = var.alb_name

  load_balancer_type = "application"
  subnets            = [aws_subnet.public1.id, aws_subnet.public2.id]
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.tutorial.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

resource "aws_lb_target_group" "asg" {

  name = var.alb_name

  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.tutorial.id
}

resource "aws_security_group" "alb" {

  name = var.alb_security_group_name
  vpc_id      = aws_vpc.tutorial.id

  # Allow inbound HTTP requests
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "default" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  name                 = "mydb"
  username             = "foo"
  password             = "foobarbaz"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.selected.name
}

resource "aws_db_subnet_group" "selected" {
  name       = "main"
  subnet_ids = [ aws_subnet.private1.id, aws_subnet.private2.id ]
  # module.vpc.private_subnets

  tags = {
    Name = "terraform tutorial DB subnet group"
  }
}
