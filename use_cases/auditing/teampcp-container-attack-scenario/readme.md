https://www.elastic.co/security-labs/teampcp-container-attack-scenario
https://flare.io/learn/resources/blog/teampcp-cloud-native-ransomware
https://beelzebub.ai/blog/threat-huntinga-analysis-of-a-nextjs-exploit-campaign/

TeamPCP compromised Trivy first. A security scanning tool. On March 19. LiteLLM used Trivy in its own CI pipeline… so the credentials stolen from the SECURITY product were used to hijack the AI product that holds all your other credentials.

Then they hit GitHub Actions. Then Docker Hub. Then npm. Then Open VSX. Five package ecosystems in two weeks. Each breach giving them the credentials to unlock the next one.

The payload was three stages.. harvest every SSH key, cloud token, Kubernetes secret, crypto wallet, and .env file on the machine.. deploy privileged containers across every node in the cluster.. install a persistent backdoor waiting for new instructions.”

https://x.com/aakashgupta/status/2036653323978420322?s=46


This is the "Conference Keynote" version of the TeamPCP story. It is written to be delivered from a stage, with clear distinctions between the **Pod** (the entry point), the **Server** (the hijacked host), and the **Cluster** (the target territory).

---

# **Title: The Industrialized Breach: 60,000 Hijacked Hosts**

### **The Hook: The Reality of 60,000**
*(Visual: A dark screen with the number **60,000** in cold, white text.)*

"When we talk about security incidents, we often talk about 'leaks' or 'hacks.' But what happened in late 2025 and is continuing today, in March 2026, is something different. It is an **Industrial Takeover**.

A threat actor known as **TeamPCP**—or **PCPcat**—didn't just breach some apps. They hijacked **60,000 servers** worldwide. 

Let’s be very clear about what a 'server' means here. We aren't just talking about 60,000 containers or pods. We are talking about **60,000 unique Cloud Instances**. 60,000 Virtual Machines. 60,000 billable pieces of infrastructure on Azure and AWS that were forcibly recruited into a criminal botnet. 

They didn't just want your data. They wanted your **CPU cycles**, your **Network Bandwidth**, and your **Cloud Identity**."

---

### **Phase 1: The Infiltration (The Pod)**
*(Visual: A diagram of a single Container/Pod labeled "Next.js Application".)*

"The attack starts at the **Pod level**. TeamPCP uses a machine-gun approach to scanning. They hunt for a vulnerability in **Next.js Server-Side Rendering (SSR)** called **React2Shell**. 

They send one malformed request. Because the application is rendering on the server, it executes a command. Suddenly, your legitimate web pod is running a hidden script: `proxy.sh`. 

In a standard environment, that pod is now a 'Zombie.' It reaches out to the internet, downloads a scanner, and starts looking for its next victim. But a pod is just a small box. To build a global empire, TeamPCP needs to get out of the box. They need the **Server**."

---

### **Phase 2: The Escape (The Server/Node)**
*(Visual: An arrow breaking out of the Pod and pointing to the "Host/Node".)*

"This is the 'Escape' phase. TeamPCP’s scripts are designed to find the **Host Server**—the actual VM running the container engine. They try to mount the host's root filesystem (`/host`) and deploy a privileged **DaemonSet**. 

Once they own the **Server**, the game changes. 
* They install **XMRig** to mine Monero using 100% of the host's CPU. 
* They install **gost** or **frps** to turn your corporate IP into a dark-web proxy. 
* **This is where the '60,000' number comes from.** They don't just stay in the pod; they conquer the underlying server to industrialize their theft."

---

### **Phase 3: The Prevention (The OpenShift "Hard No")**
*(Visual: A heavy iron gate labeled "OpenShift Guardrails" closing over the Pod.)*

"But here is where the story shifts. If that same attack hits an **OpenShift** cluster, the 'Industrial Factory' hits a brick wall.

1.  **The SCC Block:** The script tries to run as root to escape the container. **OpenShift says No.** By default, the `restricted-v2` SCC forces the pod to run as a random, non-root user. The attacker can't write to `/usr/bin`. They can’t install their tools.
2.  **The Admission Block:** The attacker tries to deploy that privileged DaemonSet to take over the **Server**. **OpenShift says No.** The Admission Controller sees the request for host privileges and rejects it instantly because the attacker's identity doesn't have the permissions.
3.  **The RBAC Wall:** The 'Worm' script tries to talk to the Kubernetes API to find other servers to infect. **OpenShift says No.** By default, the pod's ServiceAccount has no cluster-wide RBAC permissions. It cannot list nodes, pods, or namespaces. The API call returns a `403 Forbidden`. The worm is blind—it can't map the cluster, and it can't recruit new victims.

**In OpenShift, the attack is stopped at the Pod level, so it never becomes a Server statistic.**"

---

### **Phase 4: The Vision (ACS Detection & Correlation)**
*(Visual: A radar screen showing dots connecting into a single red line.)*

"Prevention is silent. But we need to see the war. This is where **Advanced Cluster Security (ACS)** turns the noise into a narrative.

ACS doesn't just send you an alert for a 'bash' shell. It correlates the entire story:
* **The Vulnerability:** It flags that your pod is running a vulnerable version of Next.js.
* **The Drift:** It notices that a `node` process just spawned a `curl` command. That’s a 'Process Baseline' violation. 
* **The Correlation:** It assigns a **Risk Score of 10/10**. 

ACS tells the SOC: *'You aren't just seeing a bug. You are seeing a TeamPCP attempt to move from this Pod to the Server. I have already blocked the escape, but you need to patch this app.'*

And as of March 2026, ACS is even watching the **Supply Chain**. When TeamPCP poisoned the **Trivy** and **LiteLLM** images, ACS identified the 'untrusted' signatures before those pods could even start."

---

### **Phase 5: Stop Patching. Start Rebuilding.**
*(Visual: A cracked wall being replaced by poured concrete.)*

"Vulnerabilities age like milk. Attacker skills age like wine. The combination means the likelihood of exploitation permanently increases over time—and that is outside our control. What is inside our control is **impact**.

Patching is a treadmill. You will never outrun it. The real answer is to eliminate the attack surface at the source: **your base image**.

This is where **Red Hat Universal Base Images (UBI)** change the equation. Most container images in the wild are built on general-purpose OS layers—full of shells, package managers, compilers, and utilities that no production workload ever needs. TeamPCP's entire toolchain—`curl`, `wget`, `bash`, `chmod`—depends on finding those tools already present in the container.

UBI Micro and UBI Minimal strip the image down to only what the application requires. No package manager. No shell. No curl. If the tools aren't there, the attacker's scripts fail before a single line executes.

Pair that with **Red Hat's continuous CVE remediation**—base image vulnerabilities are patched and republished automatically—and you shift from 'reacting to CVEs' to 'starting clean, every build.'

**The best exploit is the one that finds nothing to exploit.**"

---

### **The Hard Truth: Compliance Is Not Security**
*(Visual: A checklist with a green checkmark — and a breach notification underneath it.)*

"Every one of those 60,000 hijacked servers probably had a compliance report that said **'Pass.'**

Think about that. The auditors signed off. The checklist was green. And the machines were still mining Monero for a criminal gang by morning.

This is the fundamental lie we tell ourselves. **Compliance is a rearview mirror.** It tells you whether you followed the rules — rules written months or years ago, by people who were not in the same room as the attacker, and who have never read a worm script.

The people who *have* read those scripts — the security researchers, the ethical hackers, the people who compete at DEF CON — they knew what React2Shell was capable of before most SOC teams had even heard the name. They had already reverse-engineered `proxy.sh`. They knew exactly how TeamPCP would pivot from Pod to Server.

But they are not writing the compliance checklists. They are not in the audit meetings. And that disconnect is what costs organizations billions every year.

**Compliance tells you the door was locked. Security tells you someone is picking the lock *right now*.**

*(Pause.)*

So what is the answer? It is not a new framework. It is not a longer checklist.

The answer is to build platforms and apply controls that are **designed the way attackers think**. When you do that — SCCs that enforce non-root by default, RBAC that gives pods zero trust, admission controls that reject privileged workloads before they start — something interesting happens.

Every one of those controls maps directly to a CIS benchmark. To a NIST control. To a PCI requirement.

**When you build for genuine security, compliance is not the goal. It is the receipt.**

You don't get there by starting with the checklist. You get there by building a platform that is genuinely hard to break — and the audit report writes itself.

Let's be honest about something. You will not catch every vulnerability before it is exploited. A library your application depends on will have a zero-day. A CVE will drop on a Friday afternoon. An attacker will get a foothold.

That is not a failure. That is reality.

The question is: **what happens next?**

In an unprotected environment, that foothold becomes a server. That server becomes ten. The SOC is fighting a wildfire with a garden hose.

In a layered platform, every step the attacker takes after that initial foothold hits a wall. They try to run as root — denied. They try to install their tools — the filesystem is read-only. They try to call out to the internet — network policy blocks the egress. They try to move laterally to other workloads — RBAC returns `403`. Each layer doesn't just slow them down; it generates a signal. ACS is correlating every one of those failed attempts into a single, high-confidence alert.

The attacker came in through a door you hadn't locked yet. But every door after that was bolted shut — and you knew the moment they tried each one.

**That is the point of defense in depth. Not to be unbreachable. To make sure a breach never becomes a catastrophe.**"

---

### **The Conclusion: Automation vs. Automation**
*(Visual: "60,000 Defended".)*

"TeamPCP is a factory. You cannot fight a factory with a manual checklist. 

You fight it with a **Platform**. You use **OpenShift** to ensure that an exploit in a **Pod** can never become a takeover of a **Server**. And you use **ACS** to give your team the 'Sentry's View' of the cluster.

The 60,000 servers they took? Those were the unprotected ones. In our clusters, the story ends at the first pod.

Thank you."

---