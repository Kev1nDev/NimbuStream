<p align="center">
  <img src="docs/architecture.svg" alt="NimbusStream" width="120">
</p>

<h1 align="center">NimbusStream</h1>

<p align="center">
  <strong>Headless GPU Cloud-Gaming Infrastructure on AWS</strong><br>
  Turn any device into a gaming PC. Stream from a cloud NVIDIA GPU with a fully encrypted WireGuard tunnel — and zero exposed attack surface.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://www.terraform.io"><img src="https://img.shields.io/badge/terraform-%3E%3D1.5-844FBA.svg" alt="Terraform"></a>
  <a href="https://aws.amazon.com/ec2/"><img src="https://img.shields.io/badge/aws-EC2-orange.svg" alt="AWS EC2"></a>
  <a href="https://www.nvidia.com/"><img src="https://img.shields.io/badge/gpu-NVIDIA%20T4%2FL4-76B900.svg" alt="NVIDIA GPU"></a>
  <a href="https://github.com/Kev1nDev/NimbuStream"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome"></a>
</p>

---

NimbusStream is an end-to-end infrastructure for cloud game streaming: a
Windows gaming VM backed by an NVIDIA GPU in AWS, rendering **headlessly** on a
virtual display and streamed to any computer at **720p/60 FPS** through a fully
encrypted **WireGuard** tunnel.

The project is a **personal cloud-gaming infrastructure exercise** — GPU-in-the-cloud
vending happens under the hood, but the exposed surface is a single WireGuard port:
**no RDP/SSH exposed to the internet**, and instances can be stopped to keep costs
near zero when unused.

## Table of Contents

- [Highlights](#highlights)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Cost Breakdown](#cost-breakdown)
- [Security Model](#security-model)
- [Repository Layout](#repository-layout)
- [Roadmap](#roadmap)
- [License](#license)

## Highlights

- **Multi-AZ custom VPC** — self-built network (`10.0.0.0/16`) with 3 subnets
  across 2 availability zones, Internet Gateway, public route tables, and
  least-privilege security groups isolating the gaming tier from the VPN tier.
- **GPU in the cloud, two tiers** — swap a single variable to move between:
  `g6.xlarge` (NVIDIA **L4**, 24 GB, flagship) and `g4dn.xlarge` (NVIDIA **T4**,
  16 GB, budget). Same tooling, no rework.
- **Headless rendering** — a Virtual Display Driver (IDD) simulates a 1280x720
  monitor. No physical display, no phantom-monitor FPS tax.
- **Low-latency streaming** — **Moonlight → Sunshine** over a LAN-optimized,
  tunable bitrate.
- **On-device LLM stack** — **Ollama** serving Llama models on the GPU instance,
  reachable only through the VPN for private inference.
- **Encrypted transport** — **WireGuard** (Curve25519) on a `t3.micro` hub;
  keys are generated locally and never transmitted.
- **Hardened by default** — IMDSv2 required, EBS encrypted with a customer KMS
  key, VPC Flow Logs to CloudWatch, restrictive NACL, RDP allowed only from the
  VPN security group, administration via SSM Session Manager (no SSH).
- **Gamepad support** — **ViGEmBus** virtual controller so clients play with any
  gamepad, no server-side hardware required.
- **Zero-cost idle** — stop instances when not playing; EIPs stay free while
  associated.

## Architecture

![Architecture diagram](docs/architecture.svg)

| Tier | Component | Role |
|---|---|---|
| Client | Moonlight (PC/Android/TV) | Decodes and renders the game stream |
| Edge | `t3.micro` WireGuard hub | Single encrypted entry point to the gaming tier |
| Gaming | `g6.xlarge` / `g4dn.xlarge` (Windows) | Headless GPU rendering + NVENC encode |
| Storage | EBS (gp3) 65 GB root + 300 GB games | OS + disposable games volume |
| Ops | SSM Session Manager, CloudWatch, KMS | No-open-port administration & auditing |

## Getting Started

> Full step-by-step guide (VDD driver, Sunshine, ViGEmBus, first stream) is in
> [docs/SETUP.md](docs/SETUP.md).

**Prerequisites**

- Terraform (>= 1.5) — OpenTofu-compatible providers.
- An AWS account with a VPC and one public subnet.
- A Windows 10/11 AMI (this repo was built against an imported AMI).
- WireGuard on your client machine.

**Deploy**

```sh
# 1. Fill in your values (VPC, subnet, AMI, WireGuard keys, SSH keys)
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# 2. Plan & apply
terraform init
terraform plan
terraform apply

# 3. Import the generated wg-client.conf into WireGuard on your PC,
#    then connect Moonlight to the gaming private IP.
```

> ⚠️ Never commit `terraform.tfvars`, `*.tfstate`, or WireGuard keys — the
> repository `.gitignore` is configured to keep them out.

## Cost Breakdown

The cost structure has two states that matter more than the hourly rate:
**running** and **stopped (idle)**.

| State | Component | Cost |
|---|---|---|
| **Running** | `g6.xlarge` GPU (Windows) | ~USD 0.80/h |
|   | `g4dn.xlarge` GPU (Windows) | ~USD 0.53/h |
|   | `t3.micro` VPN (Linux) | ~USD 0.0104/h |
|   | EIPs (associated) | USD 0 |
| **Stopped** | EBS 65 GB root + 300 GB games + 8 GB VPN | ~USD 29/mo |
|   | AMI + snapshot (65 GB) | ~USD 3.25–6.50/mo |

**Savings levers used in this project:** stop-don't-terminate, import-don't-reinstall
(AMI from a VirtualBox VMDK), no NAT gateway (~USD 32/mo saved), a *download-only*
games volume (never uploads → data-transfer cost ≈ 0), and snapshot+delete for
multi-week breaks. Full analysis: [docs/COSTS.md](docs/COSTS.md).

## Security Model

The system exposes **exactly one inbound port** to the internet.

| Surface | Exposure |
|---|---|
| WireGuard VPN (UDP 51820) | Public, `0.0.0.0/0` (client auth by key) |
| RDP (3389) | Only from the VPN security group |
| Moonlight (47984-48010) | Only from the VPN security group |
| SSH (22) | None — admin via SSM Session Manager |
| EC2 IMDS | v2-only, hop limit 1 |
| EBS | Encrypted at rest with KMS |

A full threat-model table lives in [docs/SETUP.md](docs/SETUP.md).

## Repository Layout

```
.
├── main.tf                  # EC2, VPN, security, networking
├── variables.tf             # all tunables; secrets flagged "sensitive"
├── outputs.tf               # connection strings, command helpers
├── terraform.tfvars.example # copy to terraform.tfvars and fill in
├── .github/workflows/       # CI (see Roadmap)
└── docs/
    ├── SETUP.md             # step-by-step from scratch to first stream
    ├── COSTS.md             # on-demand pricing breakdown & savings tactics
    └── CV.md                # résumé-ready project summary (EN/ES)
```

## Roadmap

- [ ] CI pipeline (terraform fmt/validate/plan on pull requests).
- [ ] Browser WebRTC player — *click & play* without installing Moonlight.
- [ ] Multi-session GPU sharing (one GPU, multiple concurrent streams).
- [ ] Spot-instance fallback for cheaper running hours.

## License

Licensed under the [MIT License](LICENSE).

---

**Acknowledgements** — built on the shoulders of great open-source:
[Sunshine](https://github.com/LizardByte/Sunshine),
[Moonlight](https://github.com/moonlight-stream), [WireGuard](https://www.wireguard.com/),
[HashiCorp Terraform](https://www.terraform.io/), and NVIDIA Cloud Gaming drivers.

> This is a personal learning/homelab project 🚧. It is not production-grade.
> Use at your own risk and never commit real secrets — see `.gitignore`.