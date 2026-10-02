import threading
import queue
import time
import datetime as dt

import boto3
import tkinter as tk
from tkinter import ttk, messagebox

import os

REGION = os.environ.get("NIMBUS_REGION", "us-east-2")
ACCOUNT_ID = os.environ.get("NIMBUS_ACCOUNT_ID", "ACCOUNT_ID")
GPU_INSTANCE = os.environ.get("NIMBUS_INSTANCE_GPU", "i-EXAMPLECOMPUTE00000")
VPN_INSTANCE = os.environ.get("NIMBUS_INSTANCE_VPN", "i-EXAMPLEVPN0000000")
INSTANCES = [
    {"id": GPU_INSTANCE, "name": "Compute", "type": "g4dn.2xlarge", "rate": 0.9328},
    {"id": VPN_INSTANCE, "name": "VPN", "type": "t3.micro", "rate": 0.0076},
]
AUTO_REFRESH_S = 30
WATCHDOG_INTERVAL_S = 300
IDLE_WINDOW_MIN = 120
NET_MIN_BPS = 2048
CPU_MAX_PCT = 10.0

ACCENT = "#27A2DF"
BG = "#0F1520"
CARD = "#161E2E"
TXT = "#DCE4EE"
DIM = "#8CA2BB"
OK = "#4ADE80"
BAD = "#F87171"

LOGFILE = __import__("os").path.join(__import__("os").path.expanduser("~"), "Desktop", "nimbus_panel.log")


def logf(msg):
    with open(LOGFILE, "a", encoding="utf-8") as f:
        f.write(dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S ") + str(msg) + "\n")


class Panel(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("NimbusPanel — Cloud GPU control")
        self.geometry("760x600")
        self.configure(bg=BG)
        self.minsize(680, 540)
        self.queue = queue.Queue()
        self.cards = {}
        self.sess_total = 0.0
        self.watch_var = tk.BooleanVar(value=False)
        self._build()
        self.after(120, self._pump)
        self._refresh_async()
        self.after(AUTO_REFRESH_S * 1000, self._auto)

    def _build(self):
        header = tk.Frame(self, bg=BG)
        header.pack(fill="x", padx=16, pady=10)
        tk.Label(header, text="NimbusPanel", font=("Segoe UI", 16, "bold"),
                 bg=BG, fg=ACCENT).pack(side="left")
        tk.Label(header, text="AWS us-east-2 · account " + ACCOUNT_ID,
                 font=("Segoe UI", 9), bg=BG, fg=DIM).pack(side="left", padx=10)
        ttk.Button(header, text="Refresh", command=self._refresh_async).pack(side="right")
        ttk.Button(header, text="Stop todo", command=self._stop_all).pack(side="right", padx=6)

        body = tk.Frame(self, bg=BG)
        body.pack(fill="both", expand=True, padx=16)

        col = 0
        for inst in INSTANCES:
            card, rows = self._make_card(body, inst)
            card.grid(row=0, column=col, sticky="nsew", padx=6, pady=6)
            body.grid_columnconfigure(col, weight=1)
            self.cards[inst["id"]] = {"inst": inst, "card": card, "rows": rows}
            col += 1
        body.grid_rowconfigure(0, weight=1)

        watch = tk.Frame(self, bg=CARD)
        watch.pack(fill="x", padx=16, pady=4)
        tk.Checkbutton(watch, text="Auto-apagado por inactividad (2 h, red≈0 AND CPU<10%)",
                       variable=self.watch_var, command=self._toggle_watch,
                       bg=CARD, fg=TXT, activebackground=CARD,
                       activeforeground=TXT, selectcolor=BG, font=("Segoe UI", 9)
                       ).pack(side="left", padx=10, pady=8)
        self.watch_lbl = tk.Label(watch, text="watchdog OFF", font=("Segoe UI", 9, "bold"),
                                  bg=CARD, fg=DIM)
        self.watch_lbl.pack(side="right", padx=10)

        tk.Label(self, text="Session cost (instances running): ",
                 font=("Segoe UI", 10, "bold"), bg=BG, fg=TXT).pack(side="left", padx=28, pady=6)
        self.cost_lbl = tk.Label(self, text="$0.00", font=("Segoe UI", 10, "bold"), bg=BG, fg=OK)
        self.cost_lbl.pack(side="left", pady=6)
        self.err_lbl = tk.Label(self, text="", font=("Segoe UI", 9), bg=BG, fg=BAD)
        self.err_lbl.pack(side="left", padx=12)

        logf = tk.Frame(self, bg=BG)
        logf.pack(fill="both", padx=16, pady=(4, 12))
        self.log = tk.Text(logf, height=6, bg="#0A0E14", fg="#AFC6DC",
                           font=("Consolas", 9), relief="flat", state="disabled")
        self.log.pack(fill="both", expand=True)
        self._log("panel arrancado")
        logf("=== panel started ===")

    def _make_card(self, parent, inst):
        card = tk.Frame(parent, bg=CARD, highlightthickness=1,
                        highlightbackground="#223046")
        tk.Label(card, text=inst["name"], font=("Segoe UI", 13, "bold"),
                 bg=CARD, fg=TXT).pack(anchor="nw", padx=12, pady=(10, 0))
        tk.Label(card, text=f"{inst['type']} — {inst['id']}", font=("Segoe UI", 9),
                 bg=CARD, fg=DIM).pack(anchor="nw", padx=12)
        rows = {}
        for key in ("state", "uptime", "ip", "cost"):
            lab = tk.Label(card, text=key.upper() + ": —", font=("Consolas", 10),
                           bg=CARD, fg=TXT)
            lab.pack(anchor="nw", padx=12, pady=(6, 0))
            rows[key] = lab
        btns = tk.Frame(card, bg=CARD)
        btns.pack(anchor="nw", padx=12, pady=10)
        ttk.Button(btns, text="Start", command=lambda iid=inst["id"]: self._start_one(iid)).pack(side="left")
        ttk.Button(btns, text="Stop", command=lambda iid=inst["id"]: self._stop_one(iid)).pack(side="left", padx=6)
        return card, rows

    def _log(self, msg):
        logf(msg)
        self.log.configure(state="normal")
        self.log.insert("end", dt.datetime.now().strftime("%H:%M:%S ") + msg + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _refresh_async(self):
        threading.Thread(target=self._fetch, daemon=True).start()

    def _fetch(self):
        try:
            ec2 = boto3.client("ec2", region_name=REGION)
            resp = ec2.describe_instances(InstanceIds=[i["id"] for i in INSTANCES])
            now = dt.datetime.now(dt.timezone.utc)
            info = {}
            total = 0.0
            for r in resp["Reservations"]:
                for in_ in r["Instances"]:
                    iid = in_["InstanceId"]
                    st = in_["State"]["Name"]
                    lt = in_["LaunchTime"]
                    uptime = max(0, (now - lt).total_seconds() / 3600) if st == "running" else 0.0
                    rate = next(i["rate"] for i in INSTANCES if i["id"] == iid)
                    cost = uptime * rate
                    total += cost
                    info[iid] = {
                        "state": st,
                        "uptime": uptime,
                        "ip": in_.get("PublicIpAddress") or in_.get("PrivateIpAddress") or "—",
                        "cost": cost,
                    }
            self.queue.put({"kind": "states", "info": info, "total": total})
        except Exception as e:
            self.queue.put({"kind": "error", "msg": str(e)})

    def _pump(self):
        try:
            while True:
                m = self.queue.get_nowait()
                if m["kind"] == "states":
                    self._apply(m["info"], m["total"])
                    self.err_lbl.config(text="")
                elif m["kind"] == "log":
                    self._log(m["msg"])
                elif m["kind"] == "error":
                    self.err_lbl.config(text="! " + m["msg"][:80])
                    self._log("ERROR: " + m["msg"])
        except queue.Empty:
            pass
        self.after(120, self._pump)

    def _apply(self, info, total):
        for iid, rows in self.cards.items():
            d = info[iid]
            color = OK if d["state"] == "running" else BAD
            rows["state"].config(text="STATE: " + d["state"].upper(), fg=color)
            if d["state"] == "running":
                rows["uptime"].config(text="UPTIME: %.1f h" % d["uptime"])
                rows["cost"].config(text="COST: $%.2f" % d["cost"])
            else:
                rows["uptime"].config(text="UPTIME: —")
                rows["cost"].config(text="COST: $0.00")
            rows["ip"].config(text="IP: " + d["ip"])
        self.sess_total = total
        self.cost_lbl.config(text="$%.2f" % total)

    def _auto(self):
        self._refresh_async()
        self.after(AUTO_REFRESH_S * 1000, self._auto)

    def _do(self, action, iids, msg):
        if not messagebox.askyesno("Confirmar", msg):
            return
        threading.Thread(target=self._worker, args=(action, iids), daemon=True).start()

    def _worker(self, action, iids):
        try:
            ec2 = boto3.client("ec2", region_name=REGION)
            if action == "start":
                ec2.start_instances(InstanceIds=iids)
                self.queue.put({"kind": "log", "msg": "start enviado: " + ", ".join(iids)})
            else:
                ec2.stop_instances(InstanceIds=iids)
                self.queue.put({"kind": "log", "msg": "stop enviado: " + ", ".join(iids)})
            self._refresh_async()
        except Exception as e:
            self.queue.put({"kind": "log", "msg": "ERROR " + str(e)})

    def _start_one(self, iid):
        self._do("start", [iid], f"Encender {iid}?\n(~$0.93/h para gaming)")

    def _stop_one(self, iid):
        self._do("stop", [iid], f"Apagar {iid}?\n(tarda ~4-7 min)")

    def _stop_all(self):
        self._do("stop", [i["id"] for i in INSTANCES], "Apagar TODAS las instancias?")

    def _toggle_watch(self):
        if self.watch_var.get():
            self.watch_lbl.config(text="watchdog ON (cada 5 min)", fg=OK)
            self._log("watchdog activado (ventana 120 min, red<2KB/s y CPU<10%)")
            threading.Thread(target=self._watchdog, daemon=True).start()
        else:
            self.watch_lbl.config(text="watchdog OFF", fg=DIM)
            self._log("watchdog desactivado")

    def _watchdog(self):
        cw = boto3.client("cloudwatch", region_name=REGION)
        ec2 = boto3.client("ec2", region_name=REGION)
        while self.watch_var.get():
            try:
                iid = INSTANCES[0]["id"]
                st = ec2.describe_instances(InstanceIds=[iid])["Reservations"][0]["Instances"][0]["State"]["Name"]
                if st == "running":
                    end = time.time()
                    start = end - IDLE_WINDOW_MIN * 60
                    tot = 0.0
                    for name in ("NetworkIn", "NetworkOut"):
                        m = cw.get_metric_statistics(
                            Namespace="AWS/EC2", MetricName=name, Dimensions=[{"Name": "InstanceId", "Value": iid}],
                            StartTime=start, EndTime=end, Period=300, Statistics=["Sum"])
                        tot += sum(p.get("Sum", 0.0) for p in m["Datapoints"])
                    avg_bps = tot / (IDLE_WINDOW_MIN * 60)
                    cpu_m = cw.get_metric_statistics(
                        Namespace="AWS/EC2", MetricName="CPUUtilization", Dimensions=[{"Name": "InstanceId", "Value": iid}],
                        StartTime=start, EndTime=end, Period=300, Statistics=["Average"])
                    avg_cpu = sum(p.get("Average", 0.0) for p in cpu_m["Datapoints"]) / max(1, len(cpu_m["Datapoints"]))
                    idle = avg_bps < NET_MIN_BPS and avg_cpu < CPU_MAX_PCT
                    self.queue.put({"kind": "log", "msg": f"watchdog: red={avg_bps:.0f}B/s cpu={avg_cpu:.1f}% -> {'APAGANDO (inactiva)' if idle else 'activa'}"})
                    if idle:
                        ec2.stop_instances(InstanceIds=[iid])
                        self._refresh_async()
                        break
            except Exception as e:
                self.queue.put({"kind": "log", "msg": "watchdog ERROR " + str(e)})
            time.sleep(WATCHDOG_INTERVAL_S)


if __name__ == "__main__":
    try:
        import boto3
    except ImportError:
        raise SystemExit("Falta boto3:  pip install boto3")
    Panel().mainloop()