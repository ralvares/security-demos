# Cheat sheet

One page to memorize. Read it the night before. Keep it next to the laptop. The full text is in
[SCRIPT.md](SCRIPT.md).

### The spine — if you forget everything, say this

Every check happens during build and during deployment — **before** the application runs.
**A clean scan is a timestamp.** RHACS keeps it fresh. But a scan only finds what is known.
It cannot see **what nobody knows yet**, **what nobody noticed**, or **what somebody hid**.
So you watch what the application **does** — and you stop it, while it happens.

### The five words

| Word | What RHACS knows | Where it pays off |
|---|---|---|
| **Made of** | libraries, packages, where it comes from | Act 1: zero CVEs. Tour: still zero |
| **Deployed** | user, privileges, secrets, exposure | Act 1: hardened. Act 3: no token, no secrets — only fake keys |
| **Talks to** | services, namespaces, the internet | Act 3: blog → payments. Act 4: three connections to the attacker |
| **Behaves** | programs, files, what is normal | Act 2: one program in the normal list. Act 4: file dropped in `/tmp` |
| **Acts** | kills the pod, shows what to block | Act 5: kill, then the network policy |

### Numbers to get right

| Number | What it is |
|---|---|
| **0** | CVEs — v1, and still v2 |
| **1** | dependency (yaegi). **1** program in the normal list: the blog itself |
| **4 hours** | RHACS rescans every running image |
| **2 · 1 · 1** | writable folders · secret · port (the Risk page) |
| **2** | trap files: `~/.aws/credentials` and `/opt/blog/.env` |
| **3** | connections to the attacker: download, mining pool, shell |
| **< 1 second** | from the attacker's command to the pod kill |
| **end of October · up to 5,000** | the backdoored Claude Code extension in the Cursor store |

### Beat by beat

| Time | Beat | Key lines | Do |
|---|---|---|---|
| 0:00 | **Slide 1 — the pipeline** | "This is my release pipeline." · "I built a small blog for today's demo." · "Every check happens during build and during deployment — before the application runs." · "Today is about what happens after deploy." · "Remember this slide. For what is missing." | Point along the jobs, then the summary, then **deploy** |
| 1:30 | **Slide 2 — the timestamp** | "A clean scan is a timestamp." · "I scanned at nine. Is it still clean now?" · "RHACS rescans every running image every four hours." · "A scan only finds what is known. Three things it cannot see." | Click the three cards |
| | *three cards* | **One:** nobody knows yet — zero-day. **Two:** nobody noticed — misconfiguration. **Three:** somebody hid — supply chain. | |
| | *what helps* | "Trusted sources. Signed images. Rescanning. Do all of it." · "It lowers the risk. It does not remove it." · Claude Code: "a trusted tool, from a trusted store — and no scanner knew." · "Watch what your applications *do*." | |
| 3:30 | **Slide 3 — five words** | Made of · Deployed · Talks to · Behaves · Acts · "Today, I test that. Live." | One word per click |
| 5:00 | **Act 1 — All green** | "This is my blog." · "First word: made of — zero." · "Second word: deployed — very short list." · "Violations: none." · **"So — is it secure?"** | Blog → Check links · Vuln Mgmt → blog:v1 · Risk · Violations. **Pause 3 s** |
| 8:00 | **The pivot** | "Writers wanted more than yes or no — a rule." · "I gave it the power to run commands." · "One clean library. Zero CVEs. And one big vulnerability." | |
| 8:30 | **Act 2 — Day zero** | "This is a zero-day. My own." · "You cannot tell a mistake from a backdoor. No scanner can." · "Fourth word: behaves." · **"A backdoor can look clean. It cannot behave clean."** | `scripts/demo.sh act2` · Violations → *Unauthorized process* |
| 12:00 | **Act 3 — Loot** | "No token. No secrets. The hardening works." · "Cloud keys!" — "**I put them there.**" · "Credit card numbers. Read by my blog." · "Nothing in the pipeline about the network." · **"Nobody decided that. Nobody noticed it."** · "Third word: talks to." | `scripts/demo.sh act3` · *Honeytoken* · slide 1 callback · *Unexpected network flow* · Network Graph |
| 17:00 | **Act 4 — Persistence and profit** | "The blog called the attacker." · "A live shell, inside my 'secure' application." · "Your cloud bill, mining for someone else." · "A rule for 'this container changed'." · **"Seeing is not stopping."** | Terminal B `scripts/attacker.sh c2` · Terminal A `scripts/demo.sh act4` · type `id`, `hostname`, `ps` · Violations · *Container drift* · Graph |
| 23:00 | **Act 5 — Respond** | "Last word: acts." · "The rules are files in Git." · "Every command costs them the pod." · "Time is what I was missing." · **"The kill stopped this attacker. The network policy stops the next one."** | `scripts/demo.sh act5` · point at Terminal B (dead) · Enforcement tab |
| 29:00 | **Act 6 — Fix forward** | "Take the rule, run it as code — that is the bug." · "Still zero CVEs." · **"Runtime security did not replace the fix. It kept me safe until the fix was ready."** | Show the diff · `scripts/demo.sh act6` |
| 32:00 | **The tour** | "The evidence is already there." · "Still zero. It was right the whole time. And it saw nothing." · five words, one line each | Violations · Graph · Risk · Vuln Mgmt |
| 37:00 | **The close** | Three questions: *Which programs should run? Would you know in one minute? How fast could you stop it?* · **"A clean scan is a timestamp. RHACS keeps it fresh. And it watches what no scan can see."** · click: "See it, and stop it, while it happens." · click: "Fix it, before the vulnerability is public." · "Thank you." | Step away from the keyboard |

### Q&A — one line each

| They ask | You say |
|---|---|
| Just a bad developer? | A normal shortcut. It passed every check. |
| We use trusted vendors. | Keep doing it. It lowers the risk. It does not remove it. |
| We sign and have SBOMs. | A signature proves who built it. Not that the code is honest. |
| We have a WAF. | Maybe it blocks this request. It has no rule for a zero-day. |
| Distroless? | Good. But attackers bring their own tools — like the miner. |
| We have EDR. | RHACS adds the context — which app, what is normal — and acts in Kubernetes. |
| Kill breaks production. | One pod, replaced in seconds. Alert first. Enforce later. |
| Anything before the kill? | Less than one second. The network policy removes even that. |
| What triggers the kill? | A program outside the normal list. |
| Port 443? | Allowed — you still see the new destination on the graph. Add an egress allow-list. |
| False alarms? | The normal list is per application. A trap file almost never. |

### Never say

"unhackable" · "we" (it is **I** — I built it) · "like yours" · "every CVE was a zero-day" ·
"nothing real to steal" · idioms
