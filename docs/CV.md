# CV — Project summary

Resume-ready summary of the project. Two versions: English (recommended for
most job markets) and Spanish.

---

## EN — "GPU-Accelerated Cloud VDI on AWS" (Personal project, 2026)

**What it is.** A self-built GPU-accelerated virtual desktop (VDI): a Windows 10 machine with an
NVIDIA L4 GPU (g6.xlarge) in AWS, rendering headlessly and streaming 720p/60 FPS
to any PC on my LAN via Moonlight/Sunshine, encrypted end-to-end on WireGuard.

**What I did.**

- Designed and provisioned the whole infrastructure as code with **Terraform**
  — EC2, VPC/public subnet routing, Security Groups, NACL, KMS-encrypted EBS,
  VPC Flow Logs, IAM roles (~33 resources).
- Solved GPU headless rendering: installed a **Virtual Display Driver (IDD/UMDF)**
  so the machine renders to a single 1280x720 virtual monitor and disabled the
  phantom generic monitors that were stealing FPS.
- Built the secure networking story: WireGuard tunnel as the only public
  surface, RDP/Moonlight reachable only through the VPN, zero inbound SSH
  (ops via **SSM Session Manager**), IMDSv2-only, EBS at rest encrypted.
- Automated unattended Windows administration in PowerShell (drivers via
  pnputil/nefcon, QoS bandwidth cap for upload, service bring-up), and made the
  whole bring-up reproducible.
- Optimized cost: stop/start discipline, public subnet (no NAT gateway,
  ~USD 32/month saved), "download-only" 300 GB data volume, and cleanup of
  orphaned EIPs/snapshots/AMIs (cut idle cost materially).

**Skills demonstrated:** Terraform · AWS (EC2, VPC, IAM, KMS, SSM, EBS, NACL) ·
Cloud GPU (NVIDIA L4, NVENC) · Linux + WireGuard · Windows automation
(PowerShell) · networking & VPN design · cost engineering.

---

## ES — "VDI acelerado con GPU en la Nube (proyecto personal, 2026)"

**Qué es.** Un escritorio virtual (VDI) con GPU en la nube: una instancia Windows 10 con GPU
NVIDIA L4 (g6.xlarge) en AWS que renderiza sin monitor físico y transmite a
720p/60 FPS por Moonlight/Sunshine a cualquier PC de mi red, cifrada de punta a
punta con WireGuard.

**Qué hice.**

- Infraestructura íntegra como código con **Terraform** (~33 recursos: EC2,
  VPC, rutas públicas, Security Groups, NACL, EBS cifrado con KMS, VPC Flow
  Logs, roles IAM).
- Render headless con GPU: instalé un **Virtual Display Driver (IDD/UMDF)**
  para exponer un único monitor virtual 1280x720 y deshabilité los monitores
  fantasma que bajaban los FPS.
- Red segura: túnel **WireGuard** como única entrada pública; RDP/Moonlight
  solo mediante la VPN; sin SSH (operación por **SSM Session Manager**);
  IMDSv2 obligatorio; discos cifrados.
- Automatización de Windows sin escritorio (PowerShell: drivers con
  pnputil/nefcon, cap de subida por QoS, arranque de servicios) y despliegue
  reproducible.
- Optimización de costos: encendido/apagado programado, subred pública (sin
  NAT gateway, ~USD 32/mes ahorrados), volumen de datos 300 GB solo-descarga,
  y limpieza de EIPs/snapshots/AMIs huérfanas.

**Skills que demuestra:** Terraform · AWS (EC2, VPC, IAM, KMS, SSM, EBS, NACL) ·
GPU en la nube (NVIDIA L4, NVENC) · Linux + WireGuard · automatización de
Windows (PowerShell) · diseño de redes/VPN · ingeniería de costos.