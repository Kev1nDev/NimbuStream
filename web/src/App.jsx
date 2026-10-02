import React, { memo, useEffect, useRef, useState } from "react";

const STAGE_W = 1280;
const STAGE_H = 660;

const NODES = {
  gpu: {
    kind: "core",
    title: "GPU WORKSTATION",
    sub: "g4dn.2xlarge · Windows Server 2019 · 1× Tesla T4 (NVENC)",
    blurb: "El corazón del sistema. La T4 (16 GB) acelera render 3D, IA y gráficos profesionales; NVENC codifica la sesión en vivo hacia tu endpoint. Ollama corre inferencia 100% local en la propia GPU.",
    tags: ["8 vCPU · 32 GB", "T4 · 16GB", "NVENC", "Ollama local"],
    stats: [["VRAM", "16 GB"], ["POWER", "75 W"], ["TEMP", "54°C"], ["LOAD", "74%"]],
    accent: "#35F0D0",
    no: "01",
  },
  ebs: {
    kind: "mini",
    title: "EBS gp3",
    sub: "350 GB · D: datos y proyectos",
    blurb: "Almacenamiento persistente cifrado con KMS CMK, montado como disco de datos (D:).",
    tags: ["350 GB", "KMS"],
    accent: "#5AA0D0",
    no: "02",
  },
  ssm: {
    kind: "mini",
    title: "SSM",
    sub: "admin sin SSH · IMDSv2 + Flow Logs",
    blurb: "Administración 100% vía AWS SSM: ni un puerto de consola abierto. Flow Logs a CloudWatch (retención 30 días).",
    tags: ["sin SSH", "ret. 30d"],
    accent: "#F0A202",
    no: "03",
  },
  vpn: {
    kind: "mini",
    title: "WireGuard pivot",
    sub: "t3.micro · UDP/51820 es el único puerto público de la cuenta",
    blurb: "El guardia de frontera. RDP y el acceso a la estación solo son posibles desde dentro del túnel.",
    tags: ["t3.micro", "UDP 51820"],
    accent: "#25D07E",
    no: "04",
  },
  sec: {
    kind: "strip",
    title: "DEFAULTS DE SEGURIDAD",
    sub: "KMS CMK · IMDSv2 · NACL deny-by-default · un solo security group",
    blurb: "Reglas heredadas del IaC: un único SG, NACL en denegación por defecto, disco cifrado. Todo declarado en Terraform.",
    tags: ["KMS", "SG único", "NACL deny"],
    accent: "#E0A62C",
    no: "05",
  },
  tunnel: {
    kind: "badge",
    title: "TÚNEL WIREGUARD",
    sub: "UDP 51820 · cifrado · par id_ed25519",
    blurb: "El conducto verde: de tu equipo al WS. Lo que viaja dentro nunca pisa Internet abierto. Un solo puerto asoma al exterior.",
    tags: ["cifrado", "id_ed25519"],
    accent: "#3FB6D8",
    no: "06",
  },
  endpoint: {
    kind: "panel",
    title: "ENDPOINT — TUS PANTALLAS",
    sub: "cliente ligero — laptop, TV, tablet",
    blurb: "Clientes ligeros que reciben la sesión codificada por NVENC y devuelven input. El cómputo vive en la nube; ellos solo dibujan.",
    tags: ["NVENC stream", "input remoto"],
    accent: "#B08FD0",
    no: "07",
  },
  privacy: {
    kind: "panel",
    title: "DATOS PRIVADOS",
    sub: "la sesión no sale del túnel",
    blurb: "El trabajo e inferencia IA quedan dentro de la VPC. Nada de telemetría a terceros.",
    tags: ["local", "privacidad"],
    accent: "#D0B0F0",
    no: "08",
  },
};

const MINIS = ["ebs", "ssm", "vpn"];
const RIGHT = ["tunnel", "endpoint", "privacy"];

const TICKER = [
  "T4 16GB · NVENC @ 90%", "WireGuard 51820 UP", "SSM online — sin SSH",
  "EBS gp3 350GB", "IMDSv2 ON", "KMS CMK activa", "llama3.2:1b cargado",
];

const START_AT = Date.now();

function fmtH(ms) {
  const s = Math.floor(ms / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const d = String(s % 60).padStart(2, "0");
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${d}`;
}

const Kpi = memo(({ kicker, value, note, accent }) => (
  <div className="kpi">
    <span className="kpi-kicker">{kicker}</span>
    <span className="kpi-value" style={{ color: accent || "var(--acc)" }}>{value}</span>
    {note && <span className="kpi-note">{note}</span>}
  </div>
));
Kpi.displayName = "Kpi";

const Tags = memo(({ tags, accent }) => (
  <div className="tags">
    {tags.map((t) => <em key={t} style={{ borderColor: accent }}>{t}</em>)}
  </div>
));
Tags.displayName = "Tags";

const NodeCard = memo(({ node, active, onSelect, labels }) => {
  const cls = "card " + node.kind + (active ? " active" : "");
  return (
    <button
      className={cls}
      style={{ "--acc": node.accent }}
      onClick={() => onSelect(node)}
      aria-pressed={active}
      aria-label={node.title}
    >
      <span className="card-no" style={{ color: node.accent }}>{node.no}</span>
      <span className="card-title" style={{ color: node.accent }}>{node.title}</span>
      {labels && <span className="card-sub">{node.sub}</span>}
      {node.stats && (
        <span className="card-stats">
          {node.stats.map(([k, v]) => (
            <span key={k} className="stat"><i>{k}</i><b>{v}</b></span>
          ))}
        </span>
      )}
      {node.tags && <Tags tags={node.tags} accent={node.accent} />}
      {node.kind === "core" && <span className="core-ring" />}
    </button>
  );
});
NodeCard.displayName = "NodeCard";

function App() {
  const [active, setActive] = useState(NODES.gpu);
  const [labels, setLabels] = useState(true);
  const [elapsed, setElapsed] = useState(0);
  const [scale, setScale] = useState(() =>
    Math.max(0.3, Math.min(1, Math.min(window.innerWidth / STAGE_W, window.innerHeight / STAGE_H)))
  );
  const [tight, setTight] = useState(() => {
    const s = Math.min(window.innerWidth / STAGE_W, window.innerHeight / STAGE_H);
    return window.innerWidth < 980 || s < 0.7;
  });
  const wrapRef = useRef(null);

  useEffect(() => {
    const id = setInterval(() => setElapsed(Date.now() - START_AT), 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    const compute = () => {
      const rw = wrapRef.current?.clientWidth || window.innerWidth;
      const rh = wrapRef.current?.clientHeight || window.innerHeight;
      const s = Math.min(rw / STAGE_W, rh / STAGE_H);
      setScale(Math.max(0.3, Math.min(1, s)));
      setTight(rw < 980 || s < 0.7);
    };
    compute();
    window.addEventListener("resize", compute);
    return () => window.removeEventListener("resize", compute);
  }, []);

  const select = (node) => setActive(node);

  return (
    <div className={"deck" + (tight ? " tight" : "")} ref={wrapRef}>
      <div className="noise" />
      <div className="stage" style={{ transform: `translate(-50%,-50%) scale(${scale})`, width: STAGE_W, height: STAGE_H }}>

        <header className="mast">
          <div className="brand">
            <span className="brand-mark">◉</span>
            <span className="brand-name">NIMBUS</span>
            <span className="brand-sub">// CONTROL DECK</span>
          </div>
          <div className="mast-title">
            <h1>cloud gpu workstation</h1>
            <p>AWS + WireGuard · estación de trabajo en la nube</p>
          </div>
          <div className="mast-side">
            <button className="ghost" onClick={() => setLabels(!labels)} aria-pressed={labels}>
              {labels ? "ocultar" : "mostrar"} etiquetas
            </button>
            <div className="clock">{fmtH(elapsed)}<i>uptime</i></div>
          </div>
        </header>

        <div className="status" key={active.title}>
          <span className="status-arrow" style={{ color: active.accent }}>▶</span>
          <span className="status-title">{active.title}</span>
          <span className="status-blurb">{active.blurb}</span>
          <Tags tags={active.tags} accent={active.accent} />
        </div>

        <svg className="wires" viewBox={`0 0 ${STAGE_W} ${STAGE_H}`} aria-hidden="true">
          <path d="M 800 240 C 816 240, 814 190, 1006 190" className="flow" />
          <path d="M 1030 242 C 1030 300, 1030 330, 1030 364" className="flow" style={{ strokeDasharray: "10 8" }} />
        </svg>

        <section className="region" aria-label="Región AWS">
          <div className="region-head">
            <span className="region-kicker">REGION</span>
            <span className="region-name">AWS · us-east-2</span>
          </div>
          <div className="region-body">
            <NodeCard node={NODES.gpu} active={active === NODES.gpu} onSelect={select} labels={labels} />
            <div className="minis">
              {MINIS.map((k) => (
                <NodeCard key={k} node={NODES[k]} active={active === NODES[k]} onSelect={select} labels={labels} />
              ))}
            </div>
            <NodeCard node={NODES.sec} active={active === NODES.sec} onSelect={select} labels={labels} />
          </div>
        </section>

        <aside className="rail-col" aria-label="Red y clientes">
          {RIGHT.map((k) => (
            <NodeCard key={k} node={NODES[k]} active={active === NODES[k]} onSelect={select} labels={labels} />
          ))}
        </aside>

        <footer className="kpis">
          <Kpi kicker="RENDER" value="8 vCPU" note="32 GB RAM · elástico bajo demanda" accent="var(--acc)" />
          <Kpi kicker="VRAM" value="16 GB" note="Tesla T4 · NVENC dedicado" accent="var(--acc)" />
          <Kpi kicker="LATENCIA" value="2-5 ms" note="ruta cifrada por el túnel" accent="var(--amber)" />
          <Kpi kicker="ADMIN" value="SSM" note="sin SSH · IMDSv2" accent="var(--amber)" />
          <div className="kpi ticker" aria-hidden="true">
            <span>
              {[...TICKER, ...TICKER].map((t, i) => <em key={i}>{t}<i>◆</i></em>)}
            </span>
          </div>
        </footer>

      </div>
    </div>
  );
}

export default App;