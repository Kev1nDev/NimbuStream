variable "aws_region" {
  description = "Region de AWS"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "ID de la VPC existente (BascoVpc)"
  type        = string
}

variable "public_subnet_id" {
  description = "ID de la subred que sera publica (Basco-Subnet-G5, 10.0.1.0/24)"
  type        = string
}

variable "gaming_ami_id" {
  description = "ID de la AMI Windows importada desde VirtualBox"
  type        = string
}

variable "gaming_instance_type" {
  description = "Tipo de instancia gaming. g4dn.xlarge (T4) o g5.xlarge (A10G)"
  type        = string
  default     = "g4dn.xlarge"
}

variable "gaming_root_volume_size" {
  description = "Tamano del volumen raiz en GB (la AMI trae 65)"
  type        = number
  default     = 65
}

variable "games_volume_size" {
  description = "GB del volumen desechable para juegos (0 = no crear). Se crea VACIO en AWS (sin subir nada), solo se descargan archivos."
  type        = number
  default     = 0
}

variable "games_volume_snapshot_id" {
  description = "Snapshot opcional desde el cual restaurar el volumen de juegos (para recuperar la biblioteca sin redescsrcargar). Vacio = crear volumen nuevo."
  type        = string
  default     = ""
}

variable "vpn_instance_type" {
  description = "Tipo de la instancia VPN (t3.micro = free tier)"
  type        = string
  default     = "t3.micro"
}

variable "vpn_root_volume_size" {
  description = "GB del volumen raiz de la VPN"
  type        = number
  default     = 8
}

variable "ssh_public_key_path" {
  description = "Ruta de la clave publica ED25519 (id_ed25519.pub) para el key pair del VPN (Ubuntu)"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Ruta de la clave PRIVADA ED25519 (id_ed25519) del VPN"
  type        = string
}

variable "windows_key_public_path" {
  description = "Ruta de la clave publica RSA para Windows (ED25519 NO soportado por AMIs Windows)"
  type        = string
  default     = "/home/USER/.ssh/id_rsa_aws.pub"
}

variable "windows_key_private_path" {
  description = "Ruta de la clave PRIVADA RSA de Windows (para descifrar contrasena de Administrator)"
  type        = string
  default     = "/home/USER/.ssh/id_rsa_aws"
}

variable "gaming_outbound_throttle_bps" {
  description = "Limite de ancho de banda de SUBIDA (bits/seg) aplicado via NetQosPolicy en Windows. 20000000 = 20 Mbps"
  type        = number
  default     = 20000000
}

variable "streaming_enabled" {
  description = "Habilitar puertos de streaming Moonlight/Sunshine (solo accesibles via VPN)"
  type        = bool
  default     = true
}

variable "wg_server_private_key" {
  description = "Clave PRIVADA del servidor WireGuard (solo bootstrap, nunca compartir)"
  type        = string
  sensitive   = true
}

variable "wg_server_public_key" {
  description = "Clave publica del servidor WireGuard"
  type        = string
}

variable "wg_client_private_key" {
  description = "Clave PRIVADA del cliente (tu PC)"
  type        = string
  sensitive   = true
}

variable "wg_client_public_key" {
  description = "Clave publica del cliente (tu PC)"
  type        = string
}