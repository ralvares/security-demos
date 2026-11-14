# RHACS - Threat Detection and Response: the talk, word for word

**40 minutes.** Spoken text is plain. Stage directions are in *[italics in brackets]*.
⏱ marks where you should be on the clock. Pauses are part of the script — take them.

Written in simple English: short sentences, common words, no idioms. The key messages repeat on
purpose — it helps people who are listening in a second language.

**The three threads** — three ways a security hole gets into an application with a green pipeline:

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
people read. They will smile at "Looks unhackable. Ship it."]*

This is a release pipeline. I think it looks a lot like yours.

We built a small blog. Before it went to production, it passed every step.

*[Point along the jobs.]*

Build. Image scan. Policy check. Security approval. Deploy.

*[Point down the summary.]*

The image scan found zero vulnerabilities. Zero. Not low. Zero.

The application uses one small open-source library — and it has zero CVEs. The base image is up to
date. There is no package manager
inside.

It runs without root. Its files are read-only. It has no extra privileges. It has no Kubernetes token.

The policy check found no problems. It has the lowest risk in the whole cluster.

*[Point at the security approval.]*

And the security team said: "Looks unhackable. Ship it."

*[Pause.]*

Everything on this slide is true. In a few minutes, you will see it all in the console.

So today, we will find out what a green pipeline is really worth.

*[Pause.]*

And one more thing. Remember this slide. Not for what is on it. For what is missing.

---

## ⏱ 1:30 — Slide 2: the timestamp

*[Slide 2: one line — "A clean scan is a timestamp."]*

Here is the problem with everything in that pipeline.

We checked it all *before* we deployed. The libraries. The base image. The settings.

So every green check is true at one moment. The moment we checked.

If we scanned at nine o'clock this morning, the application was clean at nine o'clock this morning.

Is it still clean now?

*[Pause.]*

We don't know. Because new vulnerabilities are found every day. In libraries. In base images. In our
own code. They are found faster than ever. And the time to fix them is getting shorter.

Your image did not change. What the world knows about it did.

Here is a simple fact: every CVE was a zero-day once. On the day of the attack, there is no CVE. So
there is nothing for a scanner to find. The scanner is not wrong. It just cannot see what nobody knows
yet.

Second problem: misconfiguration. The things nobody checked, because they were not on the list.

*[Pause.]*

And the third problem is the one that worries me most. Supply-chain attacks.

Today, attackers often don't attack your application directly. They attack what your application is
built from. A library. A base image. A build tool. A step in your pipeline.

You may know the story of xz. It is a small library, inside almost every Linux system. One person
worked on it for more than two years. They became a trusted maintainer. And then they hid a backdoor
inside it.

It was found by luck. An engineer noticed that his logins were half a second slower. He looked closer,
and he found the backdoor.

So what does our pipeline do with a hidden backdoor? The scanner looks for *known* problems. A hidden
backdoor is not known. So the scan is clean. The pipeline signs the image. So the backdoor is signed
too.

*[Pause.]*

So, what can we do?

First: know where your components come from. Use trusted sources. Use trusted vendors — people who
build, check, sign and maintain their software for years. Sign your own images, and check signatures
before you run anything.

That lowers the risk a lot.

But it does not remove it. xz came from a trusted project. It was in trusted distributions.

So you need one more thing. You need to watch what your applications actually *do*.

Because a clean scan is not a guarantee. A clean scan is a timestamp.

---

## ⏱ 3:30 — Slide 3: what's watching

*[Slide 3: "Made of → Deployed → Talks to → Behaves → Acts". Show one word at a time.]*

So before I break anything, let me tell you what is watching this cluster.

Imagine a tool that knows your applications better than the people who wrote them.

*[Show: Made of.]*

It knows what each application is made of. Every library. Every package. And where it comes from —
which registry, and if the image is signed. And it knows which parts have vulnerabilities. Not only on
the day you built it. Every day.

*[Show: Deployed.]*

It knows how each application was deployed. Which user. Which privileges. Which secrets it can read.
If it can write files. If it is open to the internet.

*[Show: Talks to.]*

It knows who each application talks to. Which services. Which namespaces. Which addresses on the
internet. And also — who it has never talked to.

*[Show: Behaves.]*

And it knows how each application behaves. Which programs it runs. Which files it changes. It learns
what is normal for that one application.

*[Show: Acts.]*

So when something changes, it knows. A program that never ran before. A new file that should not
exist. A connection to a new place.

It also knows the context. How exposed the application is. What it can reach. So it can tell you how
serious the change is.

And it can act. It can stop the workload. It can close the network. Fast — before a person even reads
the alert.

*[Pause.]*

Today, we will test that.

*[Switch to the browser. No more slides — only one quick look back at slide 1 in Act 3.]*

---

## ⏱ 5:00 — Act 1: Unhackable

*[Browser: the blog home page.]*

This is our blog. The Unhackable Blog. Our marketing team chose the name. Not me.

*[Point at the third post.]*

This post is about our newest feature.

*[Click Write.]*

This is the editor. A writer pastes a text and clicks Check links —

*[Click Check links. Results appear, all green.]*

— and the blog checks every link before it is published. It is useful. The writers love it. The team
built it in one afternoon.

Now let's check what the pipeline told us.

*[RHACS → Vulnerability Management → Images without CVEs.]*

First word: **made of**.

This page shows images with no vulnerabilities. Here is our blog.

*[Click unhackable/blog:v1.]*

Zero critical. Zero important. Zero moderate. Zero low. Nothing to fix.

*[Point at the labels at the top: registry, OS, "No signature found", scan time.]*

It also shows where the image comes from. Which registry. Which operating system. And if it is signed.
Ours is not signed. In a real production system, you should sign it — and check the signature before
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

So the pipeline was right. If this was your application, you would ship it. Every check is green.

So — is it secure?

*[Pause. Three full seconds.]*

---

## ⏱ 8:00 — The pivot

Let's look at that link checker again. It was built in one afternoon. Power users wanted more than a
yes/no, so it lets them attach a little *rule* to validate a link.

How do you run a rule? With an embedded Go interpreter — a library called yaegi. It scans perfectly
clean: zero CVEs. One line of go.mod — and the scanner stayed green.

So the developer used it, and to make rules useful, handed it one more thing: the ability to run a
command. When you submit a "rule", the blog evaluates it as code.

That is a normal shortcut. Every team here has done something like it, under time pressure. It is fast.
One clean library. Zero CVEs.

*[Pause.]*

And one big security hole.

So what happens if the "link" I send is not a link — but a rule?

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

This is a zero-day. Our own zero-day. Tomorrow, it could be a library in your image. It could be a
problem nobody will discover until next month. On the day of the attack, the scanner says zero. The
scanner is right. And it does not help.

*[Pause.]*

Now a harder question. What if this was not a mistake?

What if someone added it on purpose? A bad pull request. A changed library. A hacked build step.

The code would look exactly the same. The scan would say zero. The review would see a small shortcut.

From the code alone, you cannot see if this is a mistake or a backdoor. And no scanner can.

*[RHACS → Violations.]*

So — did anyone notice?

*[Point at "TDR – Unauthorized process in the Unhackable Blog", Critical.]*

Yes. In seconds.

*[Click it.]*

Here are my exact commands. `id`. `uname`. `cat`. `head`. In which container. As which user. At what
time.

This is the fourth word: **behaves**.

RHACS has watched this application since it started. And this application runs exactly one
program: itself. It checks links by itself. It runs rules inside itself. It never starts another
program. So the normal list has one line. And we locked that list.

So anything else is someone else, running code inside our container.

And look at what the attacker used. `id`. `cat`. Normal Linux tools. Nothing an antivirus would call
"bad". RHACS does not care. It does not need to know what an attack looks like. For a zero-day, nobody knows that. It
only needs to know what normal looks like.

And it does not care who wrote the code, or why. A mistake or a backdoor — to be useful to an attacker,
it must *do* something. Run a program. Write a file. Open a connection. And that is exactly what RHACS
watches.

Remember how xz was found? Somebody noticed strange behavior. That was luck. This is not luck.

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

Cloud keys! In a hidden folder. An access key, a secret key, and a note about where the backups are.
For an attacker, this is perfect.

*[Pause.]*

We put them there.

These keys are fake. The application never reads this file. Never. So the only one who will ever read
it is someone who should not be there.

*[RHACS → Violations → TDR – Honeytoken touched.]*

This is a honeytoken. A trap. It has no false alarms, because nobody normal touches it. The attacker
took the bait. And here is the exact command.

*[Back to the terminal output.]*

Next, the attacker goes further. Can they reach the Kubernetes API? Yes, it answers. And the payment
service?

*[Point at the card data.]*

Credit card numbers. From the payment service. Read by our blog.

*[Pause.]*

Now — remember the pipeline slide? And what was missing?

*[Quick switch to slide 1, or just say it.]*

Build. Scan. Policy check. Approval. Deploy. Nothing about the network. Nothing that says who this
application may talk to.

There is no network policy. And in Kubernetes, the default is simple: everything can talk to
everything. So our public blog can reach the payment service. It can reach the Kubernetes API. It can
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

This is a live shell. Inside our "unhackable" application. Typed by a person on a computer outside our
data center.

Now the attacker wants money.

*[Terminal A continues: the miner is downloaded and started.]*

The files of the application are read-only. So they cannot install anything there. But there is one
folder they can write to: `/tmp`. So they download a crypto miner into `/tmp`, make it executable, and
start it.

*[In Terminal B, type `ps` again. The miner is there.]*

That is your cloud bill, mining money for someone else.

*[Pause.]*

*[RHACS → Violations.]*

So what did RHACS see? Everything.

*[Point down the list.]*

A reverse shell tool. A crypto miner. A program outside the normal list.

*[Click TDR – Container drift.]*

And look at this one. This is about **files**. The image never changes. The application writes to only
one folder — its own cache. So when a new file appears in `/tmp` —

*[Point at "created", then "permission changed".]*

— dropped into /tmp, and then made executable — someone is preparing tools inside the container.
Download, make executable, run. We did not write a rule for "miner". We wrote a rule for "this
container changed".

*[Network Graph. Click attacker.example.local.]*

And here is the attacker on the map. Outside the cluster. Three connections from our blog: one
download, one mining pool, one shell. All new. All flagged.

*[Turn to the audience.]*

So, in about fifteen minutes: one unknown hole — a mistake or a backdoor, it does not matter — and one
missing network setting. And with that, the attacker ran commands, looked for keys, read card data,
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

These are the rules that found the attack. We did not click them together in a screen. They are
Kubernetes files, in Git. They go through the same review and pipeline as our code.

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

Let's think about what happened. We did not patch anything. We have not fixed the bug yet. RHACS
removed the hacked pod. Kubernetes started a new, clean pod from the original image, in a few seconds.
The miner is gone. The files in `/tmp` are gone. Everything the attacker built is gone.

And every time they try again, the same thing happens. Every command costs them the pod.

So the damage is now limited to one command. And we have time.

*[Pause.]*

And time is what we were missing. Between "someone found the hole" and "the fix is in production",
there is a gap. Hours. Sometimes days. With a zero-day, you don't even know the gap has started. This
is how you stay safe during that gap.

Step two: now that we have time, close the way in. And fix the misconfiguration.

*[Act 5 continues: the NetworkPolicy is applied.]*

RHACS watched this application the whole time. So we know what it really needs: DNS, and the internet
on the web ports. Nothing else. So that is all it gets.

*[The last call is made from inside the application itself — no new program. It times out.]*

This last call is important. It does not start a new program. It runs inside the application itself.
So the kill rule has nothing to see. But the network policy does not care how. The connection is not
allowed. It times out. And the payment service now accepts no connections at all.

The kill stopped this attacker. The network policy stops the next one, before the first packet leaves.

*[RHACS → Violations → TDR – Unauthorized process → Enforcement tab.]*

And it is all recorded. "Kill Pod" — once for every attempt.

---

## ⏱ 29:00 — Act 6: Fix forward

Now, finally, let's fix the real bug.

*[Show the diff of `linkcheck_v1.go` → `linkcheck_v2.go`.]*

This is the old code. "Built in one afternoon." And here is the problem, in two lines: take the
writer's "rule", and run it as code — with the power to start programs.

And this is the fix. No more rules. Check that the link is a real web address. Use a proper web
client. Nothing is run as code. No extra programs. Nothing for an attacker to use.

We did not have to guess where the problem was. RHACS showed us which feature was attacked, how, and
from where. The fix is about ten lines.

*[Terminal A:]*

```bash
scripts/demo.sh act6
```

*[Version 2 starts. The scan still says 0 CVEs. The attack now returns only "not a valid http(s) URL".]*

Version two. Still zero CVEs. And the attack is now rejected: it is not a valid web address.

And remember: runtime security did not replace the fix. It kept us safe until the fix was ready. That
is its job.

---

## ⏱ 32:00 — The tour

Let's look back at what we saw. It is all still here.

*[RHACS → Violations, filtered to `unhackable`.]*

One attack. Many alerts. Programs, files, keys, network. Each one shows the command, the
user and the time. This is not just an alert. The investigation is already done for you.

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

Let's go back to the five words.

**Made of** — zero CVEs, and where it comes from. This is where most teams stop.

**Deployed** — hardened. And that helped. No token. Nothing real to steal.

**Talks to** — the call to payments. The calls to the attacker. The missing network policy.

**Behaves** — every command, every file. The zero-day — or the hidden backdoor.

**Acts** — the kill, and the network policy.

One product. One console. The same agents you already use for vulnerability scanning. Most teams only
use the first word. The other four stay dark.

---

## ⏱ 37:00 — The close

*[Step away from the keyboard. Leave the network graph on screen, or show a black screen.]*

So, what should you take home?

First: know where your components come from. Use trusted sources and trusted vendors. Sign and check
what you run. Scan everything. Keep doing all of it.

But remember: your pipeline can only check what you know.

It cannot check what nobody knows yet. It cannot check what nobody noticed. And it cannot check what
somebody hid.

So here are three questions for your team, on Monday morning.

Do you know which programs your containers should run?

Would you know, in one minute, if one of them ran something else?

And how fast could you stop it — without waking anyone up?

*[Pause.]*

A clean scan is a timestamp.

*[Click.]* See it, and stop it, while it happens. That is what you just saw — and you already have
the tool to do it.

*[Click.]* And fix it, before the hole is public. Many holes are found by researchers long before
anyone attacks with them. Imagine having the patched library in your hands before the rest of the
world even knows the hole exists.

Thank you.

*[Stop. No summary slide. Take questions.]*

---

## Q&A — short answers

**"Isn't this just a bad developer?"**
"No. It is a normal shortcut, made under time pressure, and it passed every check. And if it was a
library with an unknown bug, we would be in the same place. You cannot find unknown problems in
advance."

**"We only use trusted vendors and trusted libraries."**
"Good — please keep doing that. It is one of the best things you can do. But trusted sources lower the
risk; they don't remove it. xz came from a trusted project. That is why you also watch behavior."

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
"Good, keep doing that. But the attacker in the demo downloaded their own tools. Fewer tools in the
image helps. It does not fix the code, and it does not fix the network."

**"Why not have a network policy from day one?"**
"You should. That is the misconfiguration part of the story. The hard part is knowing what the policy
should say. RHACS learned what the application really needs — and we used that."

**"Kill Pod will break production."**
"It kills one pod. Kubernetes starts a new one in a few seconds. And you only turn it on when you know
what normal looks like. First alert, later enforce. Like in the demo."

**"Does the attacker get a connection before the kill?"**
"Yes, for less than one second. We measured it: about seven tenths of a second. That is why step two is
the network policy. It removes even that."

**"What can trigger the kill?"**
"Programs and files. Network alerts don't kill — you answer them with a network policy. That is why
there are two steps."

**"We already have EDR on the nodes."**
"EDR sees programs on a machine. RHACS sees them with context: which application, which image, what is
normal for it, who it talks to. And it responds in Kubernetes terms."
