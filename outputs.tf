output "vpn_instance_id" {
  description = "ID de la instancia VPN (t3.micro)"
  value       = aws_instance.vpn.id
}

output "vpn_public_ip" {
  description = "IP elastica publica del VPN WireGuard (Endpoint del cliente)"
  value       = aws_eip.vpn.public_ip
}

output "gaming_instance_id" {
  description = "ID de la instancia gaming"
  value       = aws_instance.gaming.id
}

output "gaming_public_eip" {
  description = "IP elastica publica del gaming (solo salida internet; RDP NO llega aqui)"
  value       = aws_eip.gaming.public_ip
}

output "gaming_private_ip" {
  description = "IP privada del gaming para RDP via VPN"
  value       = aws_instance.gaming.private_ip
}

output "wg_client_config_path" {
  description = "Ruta del archivo wg-client.conf listo para importar en tu PC con WireGuard"
  value       = "${path.module}/wg-client.conf"
}

output "ssm_session_commands" {
  description = "Gestion del servidor VPN via SSM Session Manager (sin SSH). Tambien desde consola AWS EC2 > Instancias > Connect > Session Manager"
  value       = <<-EOT
    aws ssm start-session --target ${aws_instance.vpn.id}
  EOT
}

output "decrypt_password_command" {
  description = "Comando para obtener la contrasena de Administrador de Windows (usa la clave RSA id_rsa_aws)"
  value       = "aws ec2 get-password-data --instance-id ${aws_instance.gaming.id} --priv-launch-key ${var.windows_key_private_path}"
}

output "connect_rdp_via_vpn" {
  description = "Conectarte por RDP (despues de activar WireGuard y apuntar mstsc a la IP privada del gaming)"
  value       = "mstsc /v:${aws_instance.gaming.private_ip}"
}

output "moonlight_host" {
  description = "IP que debes poner en Moonlight como host (siempre con WireGuard activo)"
  value       = aws_instance.gaming.private_ip
}