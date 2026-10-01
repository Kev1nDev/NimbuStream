<p align="center">
  <img src="docs/logo.png" alt="NimbusStream" width="360">
</p>

<h1 align="center">NimbusStream</h1>

<p align="center">
  <strong>Deployment automatizado de estaciones de trabajo Windows con GPU acelerada por hardware, pensado para workloads exigentes</strong><br>
  VDI headless · streaming de video en tiempo real de baja latencia · inferencia LLM local · red de acceso cifrada de superficie mínima.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <a href="#"><img src="https://img.shields.io/badge/iaac-terraform-844FBA.svg" alt="IaC: Terraform"></a>
  <a href="#"><img src="https://img.shields.io/badge/cloud-AWS%20EC2%20%26%20VPC-orange.svg" alt="Cloud: AWS"></a>
  <a href="#"><img src="https://img.shields.io/badge/gpu-NVIDIA%20T4%2FL4-76B900.svg" alt="NVIDIA GPU"></a>
</p>

---

NimbusStream provisiona una **workstation Windows con aceleración por GPU** en AWS
(estación de trabajo virtual / VDI), renderizada de forma **headless** y transmitida
en tiempo real a cualquier dispositivo de la LAN a través de un túnel cifrado.
Es la misma base tecnológica que usan verticales como **modelado 3D, CAD/render,
edición de video profesional y tareas asistidas por IA** — el caso de uso de esta
implementación es una consola de juegos, pero la ingeniería es de **infraestructura
de cómputo remoto de alto rendimiento**.

La arquitectura mantiene un principio de seguridad estricto: **exactamente un
puerto publico de entrada** (WireGuard UDP 51820). No hay RDP/SSH expuestos a
internet y el nodo de cómputo puede detenerse por completo cuando no se usa,
dejando el costo en idle cerca de cero.

## Highlights

- **Cómputo headless con aceleración por hardware** — Virtual Display Driver (IDD)
  simula un monitor virtual sin penalizacion por monitores fantasma; el encode lo hace
  el **NVENC** de la GPU (H.264/HEVC), no la CPU.
- **Estructura de red de confianza cero (single hardened ingress)** — VPC custom con
  subnet pública: la VPN WireGuard (`t3.micro`) es el único punto de entrada; el nodo
  GPU acepta tráfico solo desde el security group de la VPN. **Sin NAT gateway**
  (~USD 32/mes ahorrados), el routing de salida usa iptables del edge.
- **Tiering de GPU por variable** — cambiar una variable alterna entre
  `g4dn.xlarge` (NVIDIA **T4**, presupuesto) y `g6.xlarge` (NVIDIA **L4**, flagship),
  sin refactorizar el código.
- **IA local privada (Private Edge AI)** — **Ollama** hostea modelos open-source
  (Llama) en la VRAM de la GPU; la API de inferencia se sirve solo a través del túnel.
- **Streaming en tiempo real de baja latencia** — protocolo Sunshine/Moonlight
  sobre el túnel, bitrate ajustable; latencia típica de uso LAN:
  <60 ms medidos en operación normal.
- **Endurecimiento enterprise** — IMDSv2 obligatorio (hop limit 1), EBS cifrada con
  KMS customer-managed (rotación activa), NACL deny-by-default, VPC Flow Logs a
  CloudWatch (30 días) y operación 100% vía **SSM Session Manager** (cero SSH).
- **FinOps / Idle economy** — instancias se apagan por demanda; Elastic IPs se
  mantienen gratuitas asociadas; volumen de datos descargable y snapshot-able.
- **Gamepad virtual (opcional)** — ViGEmBus para entrada con mandos sin hardware dedicado.

## Arquitectura

![Architecture diagram](docs/architecture.svg)

| Tier | Componente | Rol |
|---|---|---|
| **Cliente** | Moonlight (PC / Android / TV) | Decodificación por hardware + render del stream |
| **Edge** | `t3.micro` WireGuard hub | Único túnel cifrado de entrada a la red |
| **Cómputo** | `g6.xlarge` / `g4dn.xlarge` (Windows) | Workstation GPU headless + encode NVENC |
| **Almacenamiento** | EBS gp3 cifrada (65 GB OS + volumen de datos) | SO + volumen de workloads/datos |
| **Ops** | SSM Session Manager · CloudWatch · KMS | Administración sin puertos, auditoría y cifrado |

El nodo GPU vive en la **subnet pública** junto al edge, pero su exposición real
es nula hacia internet: sus security groups solo aceptan RDP y streaming desde el
SG de la VPN. Todo el tráfico de entrada pasa por WireGuard.

## Getting Started

> Guía paso a paso completa (VDD, Sunshine, ViGEmBus, first stream):
> [docs/SETUP.md](docs/SETUP.md).

**Requisitos**
- Terraform (>= 1.5) u OpenTofu (el repo usa el mirror de registro de OpenTofu).
- AWS CLI autenticado con permisos para EC2/IAM/VPC.
- VPC existente con una subnet pública (el repo consume la infra existente).
- AMI Windows 10/11 importada (con **EC2Launch v2 + ENA**); claves RSA (Windows no
  soporta ED25519).
- WireGuard en la máquina cliente.

**Deploy**

```sh
cp terraform.tfvars.example terraform.tfvars   # VPC, subnet, AMI, rutas de claves, claves WG
$EDITOR terraform.tfvars
terraform init
terraform plan
terraform apply

# Password de administrador de Windows (usa tu clave RSA local)
aws ec2 get-password-data --instance-id <gaming_id> --priv-launch-key <clave_rsa>

# Config cliente generada al apply: importar wg-client.conf en WireGuard
```

> ⚠️ Nunca commitear `terraform.tfvars`, `*.tfstate` ni claves WireGuard — el
> `.gitignore` está configurado para mantenerlos fuera.

## FinOps / Topología de costos

Dos estados importan más que el precio por hora: **en uso** y **apagado (idle)**.

| Estado | Componente | Costo |
|---|---|---|
| **En uso** | `g6.xlarge` (L4, Windows) | ~USD 0.80/h |
|   | `g4dn.xlarge` (T4, Windows) | ~USD 0.53/h |
|   | `t3.micro` VPN (Linux) | ~USD 0.01/h |
|   | Elastic IPs (asociadas) | USD 0 |
| **Apagado** | EBS cifrada (65+300+8 GB) | ~USD 29/mo |
|   | AMI + snapshot | ~USD 3.25-6.50/mo |

**Palancas FinOps aplicadas:** sin NAT gateway (~USD 32/mo), stop-don't-terminate,
AMI importada (sin reinstalar SO), volumen de datos *solo-descarga* (costo de
subida ≈ 0), y ciclo snapshot-and-destroy para inactividad larga. Detalle completo:
[docs/COSTS.md](docs/COSTS.md).

## Security Model

La superficie de internet se reduce a **un solo puerto UDP**.

| Superficie | Política |
|---|---|
| WireGuard (UDP 51820) | Público; solo autentica con claves Curve25519 |
| RDP (3389) | Solo desde el security group de la VPN |
| Streaming (47984-48010 / 47998-48010) | Solo desde el security group de la VPN |
| SSH / WinRM | Deshabilitados; administración por SSM Session Manager |
| EC2 IMDS | v2-only, hop limit 1 |
| EBS | Cifrada en reposo con KMS (customer-managed) |

Threat model completo: [docs/SETUP.md](docs/SETUP.md).

## Repository Layout

```
.
├── main.tf                  # EC2, VPN, red, seguridad (EWG)
├── variables.tf             # todos los tunables (secretos marcados sensitive)
├── outputs.tf               # strings de conexión y helpers
├── terraform.tfvars.example # copiar a terraform.tfvars y llenar
└── docs/
    ├── SETUP.md             # de cero al primer stream
    ├── COSTS.md             # breakdown de precios y palancas de ahorro
    └── CV.md                # resumen listo para CV (EN/ES)
```

## Roadmap

- [ ] CI/CD: `terraform fmt` + `tflint` + plan en pull requests (GitHub Actions).
- [ ] Gateway WebRTC en navegador: portal seguro para streamear sin instalar cliente.
- [ ] Particionado multi-tenant de la GPU (vGPU) para múltiples sesiones concurrentes.
- [ ] Fallback a Spot instances para bajar el costo por hora de running.

## License

[MIT](LICENSE). Agradecimientos a [Sunshine](https://github.com/LizardByte/Sunshine),
[Moonlight](https://github.com/moonlight-stream), [WireGuard](https://www.wireguard.com/),
[Terraform/OpenTofu](https://opentofu.org/) y la comunidad de drivers NVIDIA.

> Proyecto personal de aprendizaje/laboratorio (no es production-grade industrial).
> Úsalo bajo tu propio riesgo y nunca comitees secretos reales — ver `.gitignore`.