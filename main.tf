resource "aws_security_group" "main" {
  name        = "${var.name}-${var.env}"
  description = "${var.name}-${var.env}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH Port"
  }

  ingress {
    from_port   = var.port_no
    to_port     = var.port_no
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "App Port"
  }

  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = var.prometheus_servers
    description = "Prometheus Port"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group_rule" "nginx-exporter-port" {
  count             = var.name == "frontend" ? 1 : 0
  type              = "ingress"
  from_port         = 9113
  to_port           = 9113
  protocol          = "tcp"
  cidr_blocks       = var.prometheus_servers
  security_group_id = aws_security_group.main.id
}

resource "aws_security_group_rule" "grok-exporter-port" {
  count             = var.name == "frontend" ? 1 : 0
  type              = "ingress"
  from_port         = 9144
  to_port           = 9144
  protocol          = "tcp"
  cidr_blocks       = var.prometheus_servers
  security_group_id = aws_security_group.main.id
}

resource "aws_instance" "main" {
  ami                    = data.aws_ami.ami.image_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.main.id]

  root_block_device {
    volume_size = var.disk_size
  }

  tags = {
    Name      = "${var.name}-${var.env}"
    Monitor   = "yes"
    env       = var.env
    component = var.name
  }

  # this to not re-create machines on tf-apply again and again. This will not be needed later when we go with ASG
  lifecycle {
    ignore_changes = [
      "ami"
    ]
  }

}

resource "aws_route53_record" "main" {
  zone_id = var.zone_id
  name    = "${var.name}-${var.env}.rdevopsb79.online"
  type    = "A"
  ttl     = 30
  records = [aws_instance.main.private_ip]
}

resource "null_resource" "main" {
  depends_on = [aws_route53_record.main]

  triggers = {
    instance_id = aws_instance.main.id
  }

  connection {
    host     = aws_instance.main.private_ip
    user     = "ec2-user"
    password = var.SSH_PASSWORD
    type     = "ssh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo pip3.11 install hvac",
      "ansible-pull -i localhost, -U https://github.com/raghudevopsb79/expense-ansible -e role_name=${var.name} -e env=${var.env} -e vault_token=${var.vault_token} expense.yml"
    ]
  }
}

