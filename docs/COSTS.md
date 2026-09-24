# COSTS — How much does it cost, and how to keep it low

Prices below are **on-demand, us-east-2**, the region this project was built
in. Use the AWS Price List API or the console to get current numbers for your
region.

## Cost while RUNNING

| Resource | On-demand | Notes |
|---|---|---|
| `g6.xlarge` (NVIDIA L4, Windows) | ~USD 0.80/h | flagship GPU tier |
| `g4dn.xlarge` (NVIDIA T4, Windows) | ~USD 0.53/h | cheaper tier, same tooling |
| `t3.micro` (VPN, Ubuntu) | ~USD 0.0104/h | typically covered by free tier first year |
| EIPs (2, associated) | USD 0 | free while attached to a running instance |

A typical 3-hour session on the g6 ≈ **USD 2.45** (≈ USD 1.65 on the g4dn).

## Cost while STOPPED (instances off)

Instances are free when stopped, but **EBS still bills**, and so do AMIs:

| Resource | Monthly (approx) |
|---|---|
| EBS root 65 GB (gp3) | ~USD 5.20 |
| EBS games 300 GB (gp3) | ~USD 24.00 |
| EBS VPN root 8 GB (gp3) | ~USD 0.64 |
| AMI + snapshot 65 GB (EBS-based) | ~USD 3.25–6.50 |
| **Total idle per month** | **~USD 35** |

Storage is the real fixed cost. Idle is cheap, idle-with-300-GB-of-EBS is not.

## Savings levers (used in this project)

1. **Stop, don't terminate** — instances back on in minutes, EIPs stay free.
2. **Import, don't reinstall** — the Windows AMI comes from a VirtualBox VMDK
   (VMImport). No software-reinstall overhead when migrating to a bigger GPU.
3. **No NAT gateway** — gaming sits in a *public* subnet (IGW, free) instead of
   private + NAT (~USD 32/month saved).
4. **Games volume "desechable"** — the 300 GB EBS is created empty; games are
   *downloaded* into it. Nothing is ever uploaded → upload/data cost ≈ 0.
5. **Snapshot + delete for long idle** — for multi-week breaks: snapshot the
   games volume, delete the volume, restore later from the snapshot
   (~USD 24/month → ~USD 15/month, and $0 when snapshot removed after restore).
6. **AMIs/snapshots cleanup** — old duplicate AMIs and their snapshots bill
   silently; delete stale ones (and release unassociated EIPs).
7. **On-demand PKI**: g6 is cheaper per-FPS than g5 (A10G) here; both beat
   waiting on spot for a GPU box you use on a schedule.

## What to think about before scaling

- **Spot** could cut the running-hour cost ~60-70%, but g6 spot is
  hard to get at peak times — it failed on-demand retries in this project.
- **Savings Plans / Reserved (1 yr)** only pay off if you run *a lot* of hours/
  month (break-even spans when idle).
- **Bigger display** (1080p) costs FPS on the same GPU; 720p@60 keeps the
  encode load inside NVENC headroom.

> The AWS Budget alarm is a good idea for a project like this one — it catches
> accidental multi-day uptime on the g6 before it shows up in the bill.