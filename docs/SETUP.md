# SETUP — From zero to your first stream

This guide assumes you already have: an AWS account, a VPC with one public
subnet, a Windows 10/11 AMI (imported from VirtualBox/proxmox or shared by a
colleague), and Terraform installed.

> **Design note** — the whole point of this project is a *closed* surface:
> the only public inbound port is WireGuard (UDP 51820). Windows admin goes
> through SSM Session Manager; RDP and Moonlight are reachable *only through
> the VPN*. No SSH anywhere.

---

## 1. Before you start

Generate your WireGuard keypair **locally** (never transmits over the network):

```sh
wg genkey | tee server_private | wg pubkey > server_public
wg genkey | tee client_private | wg pubkey > client_public
```

Keep those files out of the repository (see `.gitignore`).

## 2. Terraform configuration

```sh
git clone <this-repo> && cd <this-repo>
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars   # VPC id, subnet id, AMI id, SSH paths, WG keys
terraform init             # uses providers mirror (see below)
terraform plan             # review 33 resources
terraform apply            # ~5-8 minutes
```

> **Provider mirror** — HashiCorp's registry is geo-blocked depending on your
> ISP/country (returns 404 with `x-amzn-waf-reason: geo`). This repo points the
> providers to the **OpenTofu registry mirror**:
> `registry.opentofu.org/hashicorp/aws` / `.../hashicorp/local`.

After apply you get: VPN + compute instances, two Elastic IPs, KMS key,
flow logs group, and a generated `wg-client.conf` for your PC.

## 3. Connect WireGuard on your PC

1. Install WireGuard from https://www.wireguard.com/install/
2. **Import tunnel from file** → select the generated `wg-client.conf`
3. Activate the tunnel
4. Test: `ping 10.66.66.1` (VPN hub)

## 4. Log into Windows (RDP through the tunnel)

```sh
# Describes the admin password on first boot (uses your RSA key)
aws ec2 get-password-data --instance-id <gaming_instance_id> \
  --priv-launch-key /home/USER/.ssh/id_rsa_aws

# Connect
mstsc /v:<gaming_private_ip>
```

Both values are printed by `terraform output`.

## 5. Install the streaming stack (in the RDP session)

### 5.1 NVIDIA driver
Install the NVIDIA Studio/Game Ready driver for the GPU. Verify:
`nvidia-smi` shows the card (L4 on `g6.xlarge`, T4 on `g4dn.xlarge`) and NVENC.

### 5.2 Virtual Display Driver (VDD) — one monitor, no phantom screens
A headless GPU has "phantom" generic monitors that steal FPS. The VDD
(an IDD/UMDF driver, e.g. MttVDD) exposes a real virtual monitor:

1. Copy `MttVDD.inf` + `MttVDD.dll` + matching `.cat` + `vdd_settings.xml`
   into `C:\ProgramData\MttVDD\`.
2. Create the root device and install the driver with **nefcon**:
   ```powershell
   nefconw.exe --create-device-node \
     --class-name Display --class-guid {4D36E968-E325-11CE-BFC1-08002BE10318} \
     --hardware-id 'Root\MttVDD'
   nefconw.exe --install-driver \
     --inf-path C:\ProgramData\MttVDD\MttVDD.inf \
     --attempt-restart-affected
   ```
3. Verify: only **one** `OK` monitor (the VDD) and `DISPLAY\MTT1337...` present.
   Disable the residual phantoms:
   ```powershell
   Disable-PnpDevice -InstanceId 'DISPLAY\DEFAULT_MONITOR\...' -Confirm:$false
   ```
4. Set `1280x720@60` in `vdd_settings.xml`. The mode activates when a client
   connects (800x600 on first boot without a logged-in session is normal).

> **nefcon** — download `nefcon_v1.20.0.zip` from the `nefarius/nefcon`
> releases page; use the **x64** `nefconw.exe`. The terse `nefcon install`
> form exits 0 without creating the device — use the explicit
> `--create-device-node` + `--install-driver` pair above.

### 5.3 Sunshine (server)
1. Install Sunshine: https://github.com/LizardByte/Sunshine
2. It registers a service (`SunshineService`). Edit
   `C:\Program Files\Sunshine\config\sunshine.conf`:
   ```ini
   encoder = nvenc
   bitrate = 20
   gamepad_driver = vigembus
   csrf_allowed_origins = https://<gaming_private_ip>
   ```
3. Forward only what your SG allows (see main.tf) — Moonlight connects via the
   compute private IP *over the VPN*.

### 5.4 ViGEmBus (virtual gamepad)
The NSIS installer (`ViGEmBus_*_x64_x86_arm64.exe /S`) often **hangs in
session 0** (unattended). Options:
- Run it inside the interactive RDP/Moonlight session (the reliable path), or
- Try it, then verify:
  ```powershell
  sc.exe query ViGEmBus      # expect: RUNNING
  Get-ChildItem C:\Windows\System32\drivers\ViGEm*
  ```
- If missing: extract the driver from the bundle and `pnputil /add-driver`.

## 6. First stream

1. On your PC: **Moonlight** → add host → compute private IP (VPN active).
2. Resolve PIN → you should get a 720p@60 desktop with the gamepad working.
3. Adjust bitrate in `sunshine.conf` if you see encoder-side network issues.

## 7. Day-2 operations

```sh
# Stop (saves ~USD 0.80/h; EIPs stay free while associated)
aws ec2 stop-instances --instance-ids <gaming_id> <vpn_id>

# Remote admin of the VPN without SSH
aws ssm start-session --target <vpn_id>

# Everything down
terraform destroy
```

## Threat model

| Threat | Mitigation |
|---|---|
| RDP exposed to internet | Allowed only from the VPN security group |
| SSH brute force | No port 22 anywhere; ops via SSM + IAM |
| Metadata theft (SSRF) | IMDSv2 `http_tokens=required`, hop limit 1 |
| Disks at rest | EBS encrypted with a dedicated KMS key (rotation on) |
| No network audit | VPC Flow Logs → CloudWatch, 30-day retention |
| Default-open firewall | Custom NACL deny-by-default + strict rules |
| EIP churn on reboot | Elastic IPs associated always |
| WireGuard keys travel | Keys generated locally, stored on your machine only |