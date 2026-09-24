terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "registry.opentofu.org/hashicorp/aws"
      version = "6.64.0"
    }
    local = {
      source  = "registry.opentofu.org/hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Data: infraestructura existente
# ---------------------------------------------------------------------------
data "aws_vpc" "basco" {
  id = var.vpc_id
}

data "aws_subnet" "public" {
  id = var.public_subnet_id
}

data "aws_ami" "windows_gaming" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "image-id"
    values = [var.gaming_ami_id]
  }
}

data "aws_ami" "ubuntu_vpn" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "image-id"
    values = ["ami-00adec9774170bad2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Internet Gateway + ruta pública (necesarios: la VPC no tenia salida)
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "basco_igw" {
  vpc_id = data.aws_vpc.basco.id

  tags = { Name = "basco-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.basco.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.basco_igw.id
  }

  tags = { Name = "basco-rt-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = data.aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Seguridad: KMS para cifrado de volumenes + NACL + Flow Logs
# ---------------------------------------------------------------------------
resource "aws_kms_key" "ebs" {
  description             = "KMS key para cifrar volumenes EBS (windows-cloud)"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = { Name = "basco-ebs-key" }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/basco-ebs"
  target_key_id = aws_kms_key.ebs.id
}

resource "aws_network_acl" "public" {
  vpc_id = data.aws_vpc.basco.id

  tags = { Name = "basco-nacl-public" }
}

resource "aws_network_acl_association" "public" {
  network_acl_id = aws_network_acl.public.id
  subnet_id      = data.aws_subnet.public.id
}

resource "aws_network_acl_rule" "in_wg" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 51820
  to_port        = 51820
}

resource "aws_network_acl_rule" "in_rdp_internal" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = data.aws_vpc.basco.cidr_block
  from_port      = 3389
  to_port        = 3389
}

resource "aws_network_acl_rule" "in_ephemeral_tcp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 130
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "in_ephemeral_udp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 131
  egress         = false
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "in_icmp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 140
  egress         = false
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = -1
  to_port        = -1
}

resource "aws_network_acl_rule" "out_all_tcp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 65535
}

resource "aws_network_acl_rule" "out_all_udp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = true
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 65535
}

resource "aws_network_acl_rule" "out_icmp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = true
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = -1
  to_port        = -1
}

resource "aws_cloudwatch_log_group" "flowlogs" {
  name              = "/aws/vpc/flowlogs/basco-vpc"
  retention_in_days = 30
}

data "aws_iam_policy_document" "flowlogs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flowlogs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "flowlogs" {
  name               = "basco-vpc-flowlogs-role"
  assume_role_policy = data.aws_iam_policy_document.flowlogs_assume.json
}

resource "aws_iam_role_policy" "flowlogs" {
  name   = "flowlogs"
  role   = aws_iam_role.flowlogs.id
  policy = data.aws_iam_policy_document.flowlogs.json
}

resource "aws_flow_log" "public_subnet" {
  iam_role_arn    = aws_iam_role.flowlogs.arn
  log_destination = aws_cloudwatch_log_group.flowlogs.arn
  traffic_type    = "ALL"
  vpc_id          = data.aws_vpc.basco.id
}

# ---------------------------------------------------------------------------
# Key pairs (clave SSH ya existente del usuario)
# ---------------------------------------------------------------------------
resource "aws_key_pair" "windows" {
  key_name   = "basco-windows-key"
  public_key = file(var.windows_key_public_path)
}

resource "aws_key_pair" "vpn" {
  key_name   = "basco-vpn-key"
  public_key = file(var.ssh_public_key_path)
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------
# SG del VPN: SOLO WireGuard (UDP 51820). Gestion via SSM Session Manager
# (sin SSH expuesto: SSM usa HTTPS saliente y IAM para autenticar)
resource "aws_security_group" "vpn" {
  name        = "basco-sg-vpn"
  description = "WireGuard server, gestion via SSM"
  vpc_id      = data.aws_vpc.basco.id

  ingress {
    description = "WireGuard"
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "basco-sg-vpn" }
}

# SG del gaming: RDP SOLO desde el SG del VPN, nada mas hacia adentro
resource "aws_security_group" "gaming" {
  name        = "basco-sg-gaming"
  description = "Windows gaming: RDP + Moonlight solo via VPN"
  vpc_id      = data.aws_vpc.basco.id

  ingress {
    description     = "RDP via VPN"
    from_port       = 3389
    to_port         = 3389
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }

  dynamic "ingress" {
    for_each = var.streaming_enabled ? [1] : []
    content {
      description     = "Moonlight/Sunshine via VPN"
      from_port       = 47984
      to_port         = 48010
      protocol        = "tcp"
      security_groups = [aws_security_group.vpn.id]
    }
  }

  dynamic "ingress" {
    for_each = var.streaming_enabled ? [1] : []
    content {
      description     = "Moonlight UDP via VPN"
      from_port       = 47998
      to_port         = 48010
      protocol        = "udp"
      security_groups = [aws_security_group.vpn.id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "basco-sg-gaming" }
}

# ---------------------------------------------------------------------------
# IAM para SSM Session Manager (gestion del VPN sin SSH)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ssm_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpn_ssm" {
  name               = "basco-vpn-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume.json
}

resource "aws_iam_role_policy_attachment" "vpn_ssm" {
  role       = aws_iam_role.vpn_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "vpn_ssm" {
  name = "basco-vpn-ssm-profile"
  role = aws_iam_role.vpn_ssm.name
}

# ---------------------------------------------------------------------------
# Instancia VPN: t3.micro Ubuntu + WireGuard
# ---------------------------------------------------------------------------
locals {
  wg_server_private_key = var.wg_server_private_key
  wg_client_public_key  = var.wg_client_public_key
  wg_subnet             = "10.66.66.0/24"
  wg_server_ip          = "10.66.66.1"
  wg_client_ip          = "10.66.66.2"
}

resource "aws_eip" "vpn" {
  domain = "vpc"
}

resource "aws_eip_association" "vpn" {
  instance_id   = aws_instance.vpn.id
  allocation_id = aws_eip.vpn.id
}

resource "aws_instance" "vpn" {
  ami           = data.aws_ami.ubuntu_vpn.id
  instance_type = var.vpn_instance_type
  key_name      = aws_key_pair.vpn.key_name

  subnet_id                   = data.aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.vpn.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.vpn_ssm.name
  monitoring                  = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.vpn_root_volume_size
    encrypted   = true
    kms_key_id  = aws_kms_key.ebs.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = <<-EOT
    #!/bin/bash
    set -e
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard iptables
    sysctl -w net.ipv4.ip_forward=1
    echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-wireguard.conf

    cat > /etc/wireguard/wg0.conf <<'WGEOF'
    [Interface]
    Address = ${local.wg_server_ip}/24
    ListenPort = 51820
    PrivateKey = ${local.wg_server_private_key}
    PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

    [Peer]
    PublicKey = ${local.wg_client_public_key}
    AllowedIPs = ${local.wg_client_ip}/32
    WGEOF

    chmod 600 /etc/wireguard/wg0.conf
    systemctl enable wg-quick@wg0
    wg-quick up wg0
  EOT

  tags = { Name = "basco-vpn-wireguard" }
}

# ---------------------------------------------------------------------------
# Instancia gaming: Windows (AMI importada)
# ---------------------------------------------------------------------------
resource "aws_eip" "gaming" {
  domain = "vpc"
}

resource "aws_eip_association" "gaming" {
  instance_id   = aws_instance.gaming.id
  allocation_id = aws_eip.gaming.id
}

resource "aws_instance" "gaming" {
  ami           = data.aws_ami.windows_gaming.id
  instance_type = var.gaming_instance_type
  key_name      = aws_key_pair.windows.key_name

  subnet_id                   = data.aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.gaming.id]
  associate_public_ip_address = true
  monitoring                  = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.gaming_root_volume_size
    encrypted             = true
    kms_key_id            = aws_kms_key.ebs.arn
    delete_on_termination = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data_replace_on_change = true

  user_data = <<-EOF
    <powershell>
    # Limite de SUBIDA (upload) en 20 Mbps via QoS de Windows
    New-NetQosPolicy -Name "ThrottleOutbound" -Default -NetworkProfile All -ThrottleRateActionBitsPerSecond ${var.gaming_outbound_throttle_bps}
    </powershell>
  EOF

  tags = { Name = "basco-windows-gaming" }
}

# Volumen "desechable" para juegos (creado VACIO en AWS, cifrado)
# Solo se descargan juegos ahi -> NO se sube nada = 0 de coste de subida.
# Para ahorrar: hacer snapshot + borrar el volumen (ver README) o terraform refresh.
resource "aws_ebs_volume" "games" {
  count             = var.games_volume_size > 0 ? 1 : 0
  availability_zone = aws_instance.gaming.availability_zone
  size              = var.games_volume_size
  type              = "gp3"
  encrypted         = true
  kms_key_id        = aws_kms_key.ebs.arn
  snapshot_id       = var.games_volume_snapshot_id != "" ? var.games_volume_snapshot_id : null

  tags = { Name = "basco-games-volume" }
}

resource "aws_volume_attachment" "games" {
  count       = var.games_volume_size > 0 ? 1 : 0
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.games[0].id
  instance_id = aws_instance.gaming.id
}

# Config del cliente WireGuard (tu PC) generada al apply
resource "local_file" "wg_client_conf" {
  filename = "${path.module}/wg-client.conf"
  content  = <<-EOT
    [Interface]
    Address = 10.66.66.2/32
    PrivateKey = ${var.wg_client_private_key}
    DNS = 1.1.1.1

    [Peer]
    PublicKey = ${var.wg_server_public_key}
    Endpoint = ${aws_eip.vpn.public_ip}:51820
    AllowedIPs = 10.0.0.0/16
    PersistentKeepalive = 25
  EOT
}