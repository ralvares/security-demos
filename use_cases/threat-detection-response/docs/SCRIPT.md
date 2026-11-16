# RHACS - Threat Detection and Response: the talk, word for word

**40 minutes.** Spoken text is plain. Stage directions are in *[italics in brackets]*.
⏱ marks where you should be on the clock. Pauses are part of the script — take them.

Written in simple English: short sentences, common words, no idioms. The key messages repeat on
purpose — it helps people who are listening in a second language.

**The three threads** — three ways a vulnerability gets into an application with a green pipeline:

- **What nobody knows yet** — a zero-day. There is no CVE yet, so a scanner cannot find it.
- **What nobody noticed** — a misconfiguration. Here: no network policy.
- **What somebody hid** — a supply-chain attack. A bad library, a broken build tool, a hidden change.

And one piece of advice that runs alongside: **know where your components come from.** Trusted
sources lower the risk. They do not remove it. That is why you also watch what your applications do.

Companion docs: [TALK.md](TALK.md) (run of show, speaking guide, Q&A, checklist) ·
[WALKTHROUGH.md](WALKTHROUGH.md) (what every screen looks like) · [../README.md](../README.md) (setup).

---

## ⏱ 0:00 — Slide 1: the pipeline

*[Slide 1 up: `slides/release.png` — the release pipeline, every job green. Wait a few seconds. Let
people read.]*

This is my release pipeline.

I built a small blog for today's demo. Before I deployed it, I made sure it went through the same checks
as any application before production.

*[Point along the jobs.]*

Build. Image scan. Policy check. Security approval. Deploy.

*[Point down the summary.]*

The image scan found zero vulnerabilities. Zero. Not low. Zero.

The application uses one small open-source library — and it has zero CVEs. The base image is up to
date. There is no package manager inside.

It runs without root. Its files are read-only. It has no extra privileges. It has no Kubernetes token.

The policy check found no problems. It has the lowest risk in the whole cluster.

*[Point at the security approval.]*

Every check passed. Approved for production.

*[Pause.]*

Everything on this slide is true. In a few minutes, you will see it all in the console.

*[Point at deploy-production.]*

But look where the pipeline ends: deploy. Every check happens during build and during deployment —
*before* the application runs. After deploy, the application is live. It takes traffic from the
internet. And those checks see nothing.

Today is about what happens after deploy, while the application runs. That is runtime security.

*[Pause.]*

And one more thing. Remember this slide. Not for what is on it. For what is missing.

---

## ⏱ 1:30 — Slide 2: the timestamp

*[Slide 2: "A clean scan is a timestamp."]*

Every one of those checks was done *before* the application runs. So every green check is true at one
moment: the moment I checked.

I scanned at nine o'clock this morning. Is it still clean now?

*[Pause.]*

New vulnerabilities are published every day. Your image did not change. What the world knows about it
did.

RHACS handles this. Every four hours, it scans every running image again, with the newest vulnerability
data. A new CVE this afternoon — you see it this afternoon. No rebuild. The timestamp stays fresh.

But a scan, even a fresh one, only finds what is *known*. There are three things it cannot see.

*[Click: the three cards.]*

One: what nobody knows yet. A zero-day. No CVE. No patch. Nothing for a scanner to find.

Two: what nobody noticed. A misconfiguration. A setting nobody checked.

Three: what somebody hid. A supply-chain attack. The attacker does not attack you. They attack
something you use.

*[Click: what helps.]*

So what helps? Trusted sources and trusted vendors. Signed images, checked before they run. And
rescanning, all the time. Do all of it.

*[Click: "It lowers the risk. It does not remove it."]*

It lowers the risk a lot. It does not remove it.

A recent example: Claude Code, end of October. Someone put a backdoor into the real extension, in the
Cursor store. It opened a remote connection into the developer's computer. Up to five thousand
developers installed it.

They did everything right: a trusted tool, from a trusted store. And no scanner knew about it.

So you need one more thing: watch what your applications *do*.

---

## ⏱ 3:30 — Slide 3: what's watching

*[Slide 3: "Made of → Deployed → Talks to → Behaves → Acts". Show one word at a time.]*

So what is watching this cluster? RHACS. It knows five things about every application.

*[Show: Made of.]*

What it is made of. Every library, every package. And where it comes from: which registry, and if the
image is signed.

*[Show: Deployed.]*

How it is deployed. Which user. Which privileges. Which secrets. If it is open to the internet.

*[Show: Talks to.]*

Who it talks to. Which services, which namespaces, which addresses on the internet. And who it has
never talked to.

*[Show: Behaves.]*

How it behaves. Which programs it runs. Which files it changes. What is normal for this one
application.

*[Show: Acts.]*

And it acts. A new program, a new file, a new connection — it sees the change. It can kill the pod,
automatically, before a person reads the alert. And it shows you which connections to close.

*[Pause.]*

Today, I test that. Live.

*[Switch to the browser. No more slides — only one quick look back at slide 1 in Act 3.]*

---

## ⏱ 5:00 — Act 1: All green

*[Browser: the blog home page.]*

This is my blog.

*[Point at the third post.]*

This post is about the newest feature.

*[Click Write.]*

This is the editor. A writer pastes a text and clicks Check links —

*[Click Check links. Results appear, all green.]*

— and the blog checks every link before it is published. It is useful. The writers love it. I
built it in one afternoon.

Now, what did the pipeline say?

*[RHACS → Vulnerability Management → Images without CVEs.]*

First word: **made of**.

This page shows images with no vulnerabilities. Here is my blog.

*[Click unhackable/blog:v1.]*

Zero critical. Zero important. Zero moderate. Zero low. Nothing to fix.

*[Point at the labels at the top: registry, OS, "No signature found", scan time.]*

It also shows where the image comes from. Which registry. Which operating system. And if it is signed.
Mine is not signed. In a real production system, you should sign it — and check the signature before
it runs.

*[RHACS → Risk → blog.]*

Second word: **deployed**.

This is everything about the deployment that adds risk. The list is very short. Two writable folders.
One secret. One port inside the cluster. That's all.

No root. Read-only files. No extra privileges. No Kubernetes token. So even if someone gets in, there
is no key to the cluster.

*[RHACS → Violations, filtered to the namespace.]*

And violations: none.

*[Turn to the audience.]*

So the pipeline was right. Every check is green.

So — is it secure?

*[Pause. Three full seconds.]*

---

## ⏱ 8:00 — The pivot

Look at that link checker again. Writers wanted more than a yes or no, so it lets them attach a
small *rule* to check a link.

To run the rules, I used a small Go interpreter — a library called yaegi. Zero CVEs. And to make the
rules more useful, I gave it one more thing: the power to run commands.

A normal shortcut, made under time pressure. One clean library. Zero CVEs.

*[Pause.]*

And one big vulnerability.

So what happens if I send a rule instead of a link?

---

## ⏱ 8:30 — Act 2: Day zero

*[Terminal A, large font.]*

```bash
scripts/demo.sh act2
```

*[The commands run. `id`, `uname`, `/etc/os-release` come back. Let people read.]*

I just ran my own commands inside the application. From outside. Through the website. With one form.

And this is not a CVE. There is no package to update. No security notice. Nobody in the world knows
about it — except me.

This is a zero-day. My own. Tomorrow, it could be in a library in your image. The scanner says zero.
The scanner is right. And it does not help.

*[Pause.]*

Now a harder question. What if this was not a mistake?

What if someone added it on purpose? A bad pull request. A changed library. A hacked build step. The
code would look the same. The scan would say zero.

From the code alone, you cannot tell a mistake from a backdoor. And no scanner can.

*[RHACS → Violations.]*

So — did anyone notice?

*[Point at "TDR – Unauthorized process in the Unhackable Blog", Critical.]*

Yes. In seconds.

*[Click it.]*

Here are my exact commands. `id`. `uname`. `cat`. `head`. In which container. As which user. At what
time.

This is the fourth word: **behaves**.

This application runs exactly one program: itself. It never starts another one. So its normal list
has one line. I set that list, and I locked it. Anything else is someone else.

Look at what the attacker used: `id`, `cat`. Normal Linux tools. Nothing an antivirus calls bad. RHACS
does not need to know what an attack looks like. It only needs to know what normal looks like.

And it does not care who wrote the code. A mistake or a backdoor — like the one in the Claude Code
extension — must *do* something to be useful. Run a program. Write a file. Open a connection. That is
what RHACS watches. A backdoor can look clean. It cannot behave clean.

---

## ⏱ 12:00 — Act 3: Loot

*[Terminal A.]*

```bash
scripts/demo.sh act3
```

Now think like an attacker. You are inside. What do you do first?

You look for passwords and keys.

*[The token check and environment check come back empty.]*

And here, the hardening works. There is no Kubernetes token. There are no secrets in the environment.
The pipeline did a good job.

But wait —

*[The `.aws/credentials` file appears, then the keys.]*

Cloud keys! In a hidden folder. An access key and a secret key. And a second file, the `.env`: a
database password and a payment key. For an attacker, this is perfect.

*[Pause.]*

I put them there.

These keys are fake. The application never reads these files. So the only one who reads them is
someone who should not be there.

*[RHACS → Violations → TDR – Honeytoken touched.]*

This is a honeytoken. A trap. Nobody normal touches it, so it almost never gives a false alarm. The
attacker took the bait. Here is the exact command.

*[Back to the terminal output.]*

Next, the attacker goes further. Can they reach the Kubernetes API? Yes, it answers. And the payment
service?

*[Point at the card data.]*

Credit card numbers. From the payment service. Read by my blog.

*[Pause.]*

Now — remember the pipeline slide? And what was missing?

*[Quick switch to slide 1, or just say it.]*

Build. Scan. Policy check. Approval. Deploy. Nothing about the network. Nothing that says who this
application may talk to.

There is no network policy. And in Kubernetes, the default is simple: everything can talk to
everything. So my public blog can reach the payment service. It can reach the Kubernetes API. It can
reach the whole internet.

Nobody decided that. Nobody noticed it. That is a misconfiguration.

*[RHACS → Violations → TDR – Unexpected network flow to payments-api.]*

Third word: **talks to**.

The payment service has a normal list of connections too. And it is empty. Nobody ever calls it. So the
first call from the blog is clearly someone moving through your cluster — toward your most important
data.

*[Network Graph.]*

And here it is on the map. The blog, reaching the payments.

---

## ⏱ 17:00 — Act 4: Persistence and profit

Until now, the attacker sent one command at a time, through the website. That is slow. An attacker
wants a real shell.

*[Turn to Terminal B. Make it visible.]*

This terminal is the attacker's computer. It is outside the cluster. Its name is
`attacker.example.local`. It is waiting for a call.

*[Terminal B:]*

```bash
scripts/attacker.sh c2
```

*[Terminal A:]*

```bash
scripts/demo.sh act4
```

*[The reverse shell connects. Terminal B receives it.]*

And the blog called the attacker. Out to the internet. Because nothing said it could not.

*[Type slowly in Terminal B:]*

```
id
hostname
ps
```

This is a live shell. Inside my "secure" application. Typed by a person on a computer outside the
data center.

Now the attacker wants money.

*[Terminal A continues: the miner is downloaded and started.]*

The files of the application are read-only. But there are two small folders they can write to. One is
`/tmp`. So they download a crypto miner into `/tmp`, make it executable, and start it.

*[In Terminal B, type `ps` again. The miner is there.]*

That is your cloud bill, mining money for someone else.

*[Pause.]*

*[RHACS → Violations.]*

So what did RHACS see? Every step.

*[Point down the list.]*

A reverse shell tool. A crypto miner. A program outside the normal list.

*[Click TDR – Container drift.]*

This one is about **files**. The application writes only to its own cache. So a new file in `/tmp` —

*[Point at "created", then "permission changed".]*

— made executable, is someone preparing tools inside the container. I did not write a rule for
"miner". I wrote a rule for "this container changed".

*[Network Graph. Click attacker.example.local.]*

And here is the attacker on the map. Outside the cluster. Three connections from my blog: one
download, one mining pool, one shell. All new. All outside the normal list.

*[Turn to the audience.]*

So, in about fifteen minutes: one unknown vulnerability — a mistake or a backdoor, it does not
matter — and one missing network setting. And with that, the attacker ran commands, looked for keys, read card data,
opened a shell from the internet, and started mining.

RHACS saw every step. In seconds.

But there is a problem.

*[Pause.]*

Seeing is not stopping. The miner is still running. The shell is still open.

---

## ⏱ 23:00 — Act 5: Respond

Last word: **acts**.

When you respond to an attack, you do two things, in order. First, limit the damage, now. Then, close
the way in.

*[RHACS → Policy Management, filter TDR.]*

These are the rules that found the attack. I did not click them together in a screen. They are
Kubernetes files, in Git. They go through the same review and pipeline as my code.

Step one: limit the damage.

*[Terminal A:]*

```bash
scripts/demo.sh act5
```

I am changing these rules from "tell me" to "act". If this application runs anything outside its
normal list, kill the pod.

*[Enforcement on. The attacker comes back with `id`.]*

The attacker comes back. They run a command —

*[Point at "pod KILLED by RHACS → replaced by clean …".]*

— and the pod is gone.

*[Point at Terminal B.]*

And look at the attacker's shell. Silent. Dead. Nobody is on the other side anymore.

I did not patch anything. The bug is still there. But RHACS killed the hacked pod, and Kubernetes
started a clean one from the original image, in a few seconds. The miner, the shell, the files in
`/tmp` — all gone.

Every time they try again, the same thing happens. Every command costs them the pod. And I have
time.

*[Pause.]*

Time is what I was missing. Between "someone found the vulnerability" and "the fix is in
production", there is a gap. Days. Sometimes weeks. With a zero-day, you don't even know the gap has
started. This is how you stay safe during that gap.

Step two: now that I have time, close the way in. And fix the misconfiguration.

*[Act 5 continues: the NetworkPolicy is applied.]*

This application needs only two things: DNS, and the internet on the web ports, to check links.
Nothing else. So that is all it gets.

*[The last call is made from inside the application itself — no new program. It times out.]*

This last call is important. It runs inside the application itself — no new program. So the kill rule
has nothing to see. But the network policy does not care how. The connection is not allowed. It times
out. And the payment service now accepts no connections at all.

The kill stopped this attacker. The network policy stops the next one, before the first packet leaves.

*[RHACS → Violations → TDR – Unauthorized process → Enforcement tab.]*

And it is all recorded. "Kill Pod" — once for every attempt.

---

## ⏱ 29:00 — Act 6: Fix forward

Now, finally, I fix the real bug.

*[Show the diff of `linkcheck_v1.go` → `linkcheck_v2.go`.]*

This is the old code. "Built in one afternoon." And here is the problem, in two lines: take the
writer's "rule", and run it as code — with the power to start programs.

And this is the fix. No more rules. Check that the link is a real web address, and fetch it with a
normal web client. Nothing is run as code.

I did not have to guess where the problem was. RHACS showed me which feature was attacked, how, and
from where. The fix is small.

*[Terminal A:]*

```bash
scripts/demo.sh act6
```

*[Version 2 starts. The scan still says 0 CVEs. The attack now returns only "not a valid http(s) URL".]*

Version two. Still zero CVEs. And the attack is now rejected: it is not a valid web address.

And remember: runtime security did not replace the fix. It kept me safe until the fix was ready. That
is its job.

---

## ⏱ 32:00 — The tour

Look back at what you saw. It is all still here.

*[RHACS → Violations, filtered to `unhackable`.]*

One attack. Many alerts. Programs, files, keys, network. Each one shows the command, the user and the
time. The evidence is already there.

*[Network Graph → blog → attacker.example.local.]*

Here is the whole attack as a map. Where it came from. Where it tried to go. Who the blog talked to for
the first time.

*[RHACS → Risk → blog.]*

Remember the application with the lowest risk in the cluster?

*[If the ranking moved, point at it. If not, go straight to the next stop.]*

*[RHACS → Vulnerability Management → blog:v1.]*

And this page.

*[Pause. Let people look.]*

Still zero. It was right the whole time. And it saw nothing.

*[Turn to the audience.]*

Back to the five words.

**Made of** — zero CVEs, and where it comes from.

**Deployed** — hardened. And that helped: no Kubernetes token, no secrets in the environment. The
only keys the attacker found were my trap.

**Talks to** — the call to payments. The calls to the attacker. The missing network policy.

**Behaves** — every command, every file. The zero-day — or the hidden backdoor.

**Acts** — the kill, and the network policy.

One product. One console. The same RHACS that does the vulnerability scanning. Today you saw all five
words.

---

## ⏱ 37:00 — The close

*[Step away from the keyboard. Leave the network graph on screen, or show a black screen.]*

So, what should you take home?

Keep doing every check, in the pipeline and at deploy. Trusted sources. Signatures. Scans.

But a pipeline only checks what you know. It cannot see what nobody knows yet. What nobody noticed. Or
what somebody hid.

So here are three questions for your team, on Monday morning.

Do you know which programs your containers should run?

Would you know, in one minute, if one of them ran something else?

And how fast could you stop it — without waking anyone up?

*[Pause.]*

A clean scan is a timestamp. RHACS keeps it fresh. And it watches what no scan can see.

*[Click.]* See it, and stop it, while it happens. That is what you just saw.

*[Click.]* And fix it, before the vulnerability is public. Imagine having the fixed library before
the rest of the world even knows about the vulnerability.

Thank you.

*[Stop. No summary slide. Take questions.]*

---

## Q&A — short answers

**"Isn't this just a bad developer?"**
"No. It is a normal shortcut, made under time pressure, and it passed every check. And if it was a
library with an unknown bug, the result would be the same. You cannot find unknown problems in
advance."

**"We only use trusted vendors and trusted libraries."**
"Good — please keep doing that. It is one of the best things you can do. But trusted sources lower the
risk; they don't remove it. The backdoored Claude Code extension was the real one, in a trusted store.
That is why you also watch behavior."

**"We sign our images and create SBOMs."**
"Keep doing it. A signature proves who built the image. An SBOM shows what is inside. But neither proves
the code is honest. The SolarWinds backdoor was in a correctly signed update."

**"How does RHACS catch a supply-chain backdoor?"**
"By behavior. A backdoor that does nothing is harmless. When it runs a program, writes a file or calls
home, that is outside the normal list. It does not matter who wrote the code."

**"We have a WAF."**
"A WAF may block this attack. Maybe not the next one. And it has no rule for a zero-day. RHACS does not
care how the attacker got in. It watches what they do inside."

**"Our images are distroless."**
"Good, keep doing that. Fewer tools in the image makes the attacker's work harder. But they can bring
their own tools — like the miner in the demo. And it does not fix the code, or the network."

**"Why not have a network policy from day one?"**
"You should. That is the misconfiguration part of the story. The hard part is knowing what the policy
should say. The RHACS network graph shows what each application really talks to. Start there."

**"Kill Pod will break production."**
"It kills one pod. Kubernetes starts a new one in a few seconds. And you only turn it on when you know
what normal looks like. First alert, later enforce. Like in the demo."

**"Does the attacker get a connection before the kill?"**
"Yes, for less than one second. That is why step two is the network policy. It removes even that."

**"What can trigger the kill?"**
"In the demo: a program outside the normal list. The network alert is on the payment service — you do
not kill your payment service. You answer it with a network policy. That is why there are two steps."

**"We already have EDR on the nodes."**
"Many EDR tools see programs on a machine. RHACS sees them with context: which application, which image, what is
normal for it, who it talks to. And it responds in Kubernetes terms."
