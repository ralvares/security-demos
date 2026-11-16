"""Build docs/TALK.html from docs/TALK.md + docs/SCRIPT.md as a navigable, one-section-at-a-time app.
usage: python3 -I md2html.py docs/   (writes docs/TALK.html)"""
import sys, re, html, json, pathlib
D = pathlib.Path(sys.argv[1])

def inline(t):
    t = html.escape(t, quote=False)
    codes = []
    t = re.sub(r"`([^`]+)`", lambda m: codes.append(m.group(1)) or f"\x00{len(codes)-1}\x00", t)
    t = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", r'<figure><img loading="lazy" src="\2" alt="\1"><figcaption>\1</figcaption></figure>', t)
    t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", lambda m: f'<a href="{m.group(2)}"' + ('' if m.group(2).startswith("#") else ' target="_blank" rel="noopener"') + f'>{m.group(1)}</a>', t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", t)
    t = re.sub(r"\x00(\d+)\x00", lambda m: "<code>" + codes[int(m.group(1))] + "</code>", t)
    return t

def strip(t): return re.sub(r"<[^>]+>", "", t)
def slug(t): return re.sub(r"[^a-z0-9]+", "-", strip(t).lower()).strip("-")

def blocks(lines):
    """markdown lines -> html string"""
    out, i = [], 0
    def start(l): return l.startswith(("#", ">", "|", "```", "- ", "* ", "---")) or re.match(r"^\d+\. ", l) or not l.strip()
    while i < len(lines):
        l = lines[i]
        if not l.strip(): i += 1; continue
        if l.startswith("```"):
            j = i + 1; buf = []
            while not lines[j].startswith("```"): buf.append(lines[j]); j += 1
            out.append('<pre><code>' + html.escape("\n".join(buf)) + "</code></pre>"); i = j + 1; continue
        m = re.match(r"^(#{3,4}) (.*)", l)
        if m:
            out.append(f'<h{len(m.group(1))} id="{slug(m.group(2))}">{inline(m.group(2))}</h{len(m.group(1))}>'); i += 1; continue
        if l.strip() == "---": i += 1; continue
        if l.startswith(">"):
            buf = []
            while i < len(lines) and lines[i].startswith(">"): buf.append(lines[i][1:].strip()); i += 1
            txt = "<br>".join(inline(b) for b in buf)
            cls = "key" if re.search(r"Key line|^\*\"|^<em>", txt) else "note"
            out.append(f'<blockquote class="{cls}">{txt}</blockquote>'); continue
        if l.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")]); i += 1
            t = '<div class="tw"><table><thead><tr>' + "".join(f"<th>{inline(c)}</th>" for c in rows[0]) + "</tr></thead><tbody>"
            t += "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in rows[2:])
            out.append(t + "</tbody></table></div>"); continue
        if l.startswith(("- ", "* ")) or re.match(r"^\d+\. ", l):
            ordered = bool(re.match(r"^\d+\. ", l)); items = []
            while i < len(lines) and (lines[i].startswith(("- ", "* ")) or re.match(r"^\d+\. ", lines[i]) or (lines[i].startswith("   ") and items)):
                if lines[i].startswith("   ") and not re.match(r"^\d+\. ", lines[i]): items[-1] += " " + lines[i].strip()
                else: items.append(re.sub(r"^(- |\* |\d+\. )", "", lines[i]))
                i += 1
            lis = []
            for it in items:
                cb = re.match(r"^\[( |x)\] (.*)", it)
                lis.append(f'<li class="cb"><label><input type="checkbox"> <span>{inline(cb.group(2))}</span></label></li>' if cb else f"<li>{inline(it)}</li>")
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(lis) + f"</{tag}>"); continue
        buf = []
        while i < len(lines) and not start(lines[i]): buf.append(lines[i].strip()); i += 1
        if not buf: buf.append(l.strip()); i += 1
        txt = " ".join(buf)
        if re.fullmatch(r"(\s*!\[[^\]]*\]\([^)]+\)\s*)+", txt):
            out.append('<div class="gallery">' + inline(txt) + "</div>")
        elif re.fullmatch(r"\*\[.*\]\*", txt):
            out.append('<div class="do"><span class="tag">DO</span><span>' + inline(txt[2:-2]) + "</span></div>")
        else:
            out.append(f"<p>{inline(txt)}</p>")
    h = "\n".join(out)
    return re.sub(r'</div>\s*<div class="gallery">', "", h)   # merge consecutive galleries

def sections(path):
    """split a markdown file on '## ' -> (intro_lines, [(title, lines)])"""
    lines = path.read_text(encoding="utf-8").split("\n")
    intro, secs, cur = [], [], None
    for l in lines:
        if l.startswith("## "):
            cur = (l[3:].strip(), []); secs.append(cur)
        elif cur is None:
            if not l.startswith("# "): intro.append(l)
        else: cur[1].append(l)
    return intro, secs

def h3split(lines):
    """split section lines on '### ' -> {title: lines}"""
    res, cur = {}, None
    for l in lines:
        if l.startswith("### "): cur = l[4:].strip(); res[cur] = []
        elif cur: res[cur].append(l)
    return res

t_intro, talk = sections(D / "TALK.md")
s_intro, script = sections(D / "SCRIPT.md")
T = {t: ls for t, ls in talk}

# screenshots per act, from TALK.md "Act by act — on screen"
screens = {}
for k, ls in h3split(T.get("Act by act — on screen", [])).items():
    m = re.match(r"(Act \d|Slides)", k)
    if m: screens[m.group(1)] = ls

DEMO = (
    '<div class="do"><span class="tag">DO</span><span>Before the talk, run <code>make web-terminal</code>. '
    'In the deck, the slide after "Let\'s test it." is the live demo: the five terminals, full screen. '
    'Click a terminal to type in it. While you type, the keyboard goes to the shell — change slides from the '
    '<b>presenter view</b> window, or click a window title bar first (the keyboard comes back to the slides).</span></div>'
    '<p>That is the theory. Now let\'s test it.</p>'
    '<p>On the left: the attacker. On the right: what RHACS sees, live. Watch the right side.</p>'
)

pages = []   # dict(id, group, title, time, html)
def add(group, title, html_, time=""):
    pages.append(dict(id=slug(title) or "start", group=group, title=title, time=time, html=html_))

add("Start", "Start here", blocks(t_intro))
for name in ["The arc", "The three threads", "The three slides", "The close"]:
    if name in T: add("Start", name, blocks(T[name]))
for name in ["How to speak to this room", "Before you walk on stage"]:
    if name in T: add("Prepare", name, blocks(T[name]))
for name in ["Run of show", "The attack chain — name each move for the audience"]:
    if name in T: add("Deliver", name.split(" — ")[0], blocks(T[name]))

add("Speaker notes", "About the notes", blocks(s_intro))
for title, ls in script:
    if title.lower().startswith("q&a"): continue
    m = re.match(r"⏱\s*([\d:]+)\s*[—-]\s*(.*)", title)
    time, name = (m.group(1), m.group(2)) if m else ("", title)
    body = blocks(ls)
    if name.startswith("Slide 1"):
        body = '<div class="slidevis"><img src="slides/release.png" alt="Slide 1 — the release pipeline"></div>' + body
    elif name.startswith("Slide 2"):
        body = '<div class="slidevis big"><div>A clean scan is a timestamp.</div></div>' + body
    elif name.startswith("Slide 3"):
        body = ('<div class="slidevis words">' + "".join(f"<span>{w}</span>" for w in ["Made of","Deployed","Talks to","Behaves","Acts"]) + "</div>") + body
    key = re.match(r"(Act \d)", name)
    key = key.group(1) if key else ("Slides" if name.startswith("Slide 1") else None)
    if key and key in screens:
        body += '<section class="screens"><h3>On screen — backup screenshots</h3>' + blocks(screens[key]) + "</section>"
    add("Speaker notes", name, body, time)
    if name.startswith("Slide 3"):
        add("Speaker notes", "Demo time", DEMO, "5:00")

for title, ls in talk:
    if title.startswith("Questions"): add("Q&A", "Questions you'll get", blocks(ls))
qa = [ls for t, ls in script if t.lower().startswith("q&a")]
if qa: add("Q&A", "Q&A — longer answers", blocks(qa[0]))

# unique ids
seen = set()
for p in pages:
    base, n = p["id"], 2
    while p["id"] in seen: p["id"] = f"{base}-{n}"; n += 1
    seen.add(p["id"])

groups = []
for p in pages:
    if not groups or groups[-1][0] != p["group"]: groups.append((p["group"], []))
    groups[-1][1].append(p)

nav = ""
for g, ps in groups:
    nav += f'<div class="grp"><div class="gt">{html.escape(g)}</div>'
    for p in ps:
        tm = f'<span class="tm">{p["time"]}</span>' if p["time"] else ""
        nav += f'<a href="#{p["id"]}" data-id="{p["id"]}">{tm}<span>{inline(p["title"])}</span></a>'
    nav += "</div>"

secs = ""
for i, p in enumerate(pages):
    tm = f'<span class="pill">⏱ {p["time"]}</span>' if p["time"] else ""
    secs += (f'<section class="page" id="{p["id"]}" data-i="{i}" hidden>'
             f'<div class="crumb">{html.escape(p["group"])} {tm}</div><h2>{inline(p["title"])}</h2>{p["html"]}</section>\n')

# ------------------------------------------------------------------ the audience deck (no notes)
# (notes_page_id, css_class, html). Elements with class "f" appear one per click, in order.
# Red Hat design-system icons (@rhds/icons 2.3.1, CC-BY-4.0), stored in docs/img/icons, inlined so they take CSS colour.
def ICON(n, cls="ico"):
    svg = re.sub(r"<!--.*?-->", "", (D / "img" / "icons" / f"{n}.svg").read_text()).strip()
    return svg.replace("<svg ", f'<svg class="{cls}" aria-hidden="true" ', 1)
LOGO = '<img class="rhlogo" src="img/rh-logo-on-dark.svg" alt="Red Hat">'
FIVE = [("Made of", "Libraries<br>Packages<br>Where it comes from", "container-image"),
        ("Deployed", "User<br>Privileges<br>Secrets<br>Exposure", "kubernetes-pod"),
        ("Talks to", "Services<br>Namespaces<br>The internet", "data-connections"),
        ("Behaves", "Programs<br>Files<br>What is normal", "view"),
        ("Acts", "Kills the pod<br>Shows what to block", "shield")]
FICON = {a: i for a, _, i in FIVE}
SLIDES = [
 ("slide-1-the-pipeline", "title",
  '<div class="rbar"></div>' + LOGO + '<div class="kicker">Red Hat Advanced Cluster Security</div>'
  '<h1>Threat Detection<br>and Response</h1><p class="lead">Zero CVEs. Still breached.<br>Caught in seconds.</p>'
  '<div class="byline">A live demo</div>'),
 ("slide-1-the-pipeline", "shotslide",
  '<div class="kicker">The promise</div><h2>Every step is green.</h2>'
  '<img class="shot" src="slides/release.png" alt="A release pipeline where every step is green">'),
 ("slide-2-the-timestamp", "statement",
  '<p class="big">A clean scan is a <em>timestamp</em>.</p>'
  '<p class="lead f">True at 9:00 this morning.<br>Is it still true now?</p>'),
 ("slide-2-the-timestamp", "",
  '<div class="kicker">The problem</div><h2>Three things no scanner can see</h2><div class="cols">'
  + "".join(f'<div class="card f">{ICON(ic)}<h3>{a}</h3><p>{b}</p></div>' for a, b, ic in [
      ("What nobody knows yet", "Zero-days. No CVE yet, so there is nothing to find.", "vulnerability"),
      ("What nobody noticed", "Misconfiguration. It is not on any checklist.", "gear"),
      ("What somebody hid", "Supply-chain attacks. Scanned, signed, and still bad.", "container-unsecured")])
  + '</div>'),
 ("slide-2-the-timestamp", "",
  '<div class="kicker">What helps</div><h2>Know where your components come from.</h2><ul class="ticks icons">'
  f'<li>{ICON("certification")}Trusted sources and trusted vendors</li><li>{ICON("container-secured")}Signed images, verified before they run</li>'
  f'<li>{ICON("calendar")}Rescan every running image every 4 hours, not only at build time</li></ul>'
  '<p class="punch f">It lowers the risk. <em>It does not remove it.</em></p>'),
 ("slide-3-what-s-watching", "",
  '<div class="kicker">What is watching</div><h2>One tool that knows every application</h2><div class="words">'
  + "".join(f'<div class="word f{" act" if a == "Acts" else ""}">{ICON(i)}<h3>{a}</h3><p>{b}</p></div>' for a, b, i in FIVE)
  + '</div>'),
 ("demo-time", "title",
  '<div class="rbar"></div><div class="kicker">Demo</div><h1>Let\'s test it.</h1>'
  '<p class="lead">One application. Zero CVEs. Every check green.</p>'
  '<div class="byline">Left: the attacker &nbsp;·&nbsp; Right: what RHACS sees</div>'),
 ("act-1-unhackable", "term", '<div class="termph"><span>Live demo terminals</span></div>'),
 ("the-tour", "",
  '<div class="kicker">What we saw</div><h2>One attack. Five words.</h2><div class="recap">'
  + "".join(f'<div class="row f">{ICON(FICON[a])}<b>{a}</b><span>{b}</span></div>' for a, b in [
      ("Made of", "Zero CVEs. Still zero."),
      ("Deployed", "Hardened. Nothing real to steal."),
      ("Talks to", "Every new connection is flagged."),
      ("Behaves", "Every command, every file. In seconds."),
      ("Acts", "Pod killed in under one second. Network closed.")])
  + '</div>'),
 ("the-close-2", "",
  '<div class="kicker">For Monday morning</div><h2>Three questions for your team</h2><ol class="qs">'
  '<li class="f">Do you know which programs your containers should run?</li>'
  '<li class="f">Would you know, in one minute, if one of them ran something else?</li>'
  '<li class="f">How fast could you stop it, without waking anyone up?</li></ol>'),
 ("the-close-2", "statement",
  '<p class="big">A clean scan is a <em>timestamp</em>.</p>'
  '<p class="lead f">Keep it fresh. Watch what no scan can see.</p>'
  f'<p class="lead f withico">{ICON("view")}<span>See it and stop it, <em>while it happens</em>.</span></p>'
  f'<p class="lead f withico">{ICON("wrench")}<span>Fix it, <em>before the vulnerability is public</em>.</span></p>'),
 ("questions-you-ll-get", "title",
  '<div class="rbar"></div>' + LOGO + '<h1>Thank you.</h1><p class="lead">Questions?</p>'
  '<div class="byline">Red Hat Advanced Cluster Security</div>'),
]
ids = {p["id"] for p in pages}
for n, _, _ in SLIDES: assert n in ids, f"notes page missing: {n}"
deck_html = ""
for i, (notes, cls, body_) in enumerate(SLIDES, 1):
    foot = "" if cls in ("title", "term") else f'<div class="foot"><span>Red Hat Advanced Cluster Security</span><span>{i}</span></div>'
    deck_html += f'<section class="slide {cls}" data-notes="{notes}">{body_}{foot}</section>\n'

TERMS = [("attacker", "1 · Attacker", "type here:  pwn 'id'  ·  link https://…", 7681, "#2e1b1b", "#ff6b6b", 20),
         ("c2", "2 · C2 - the attacker's laptop", "nc listening on :4444", 7682, "#2b2318", "#f5a623", 18),
         ("rhacs", "3 · RHACS - live violations", "", 7683, "#16242e", "#4da3ff", 18),
         ("blog", "4 · Blog - app logs", "every attack is just a “link check”", 7684, "#142620", "#3fb950", 16),
         ("pods", "5 · Pods - kill + restart", "", 7685, "#201b2e", "#b392f0", 16)]
def panel(t):
    n, label, hint, port, bg, dot, fs = t
    return (f'<div class="tp" data-name="{n}" data-port="{port}" data-fs="{fs}" data-label="{html.escape(label)}" style="--bgc:{bg};--dot:{dot}">'
            f'<div class="th" title="Drag to move · double-click to maximize"><i class="dot"></i><b>{html.escape(label)}</b><small>{html.escape(hint)}</small>'
            f'<span class="wb"><button class="wfm" title="Smaller text">A−</button><button class="wfp" title="Bigger text">A+</button><button class="wrst" title="Restart this terminal from zero (click twice)">↻</button><button class="wmin" title="Minimize">_</button><button class="wmax" title="Maximize / restore">□</button></span></div>'
            f'<div class="tb"></div></div>')
terms_html = "".join(panel(t) for t in TERMS)
LAYOUTS = [("all", "All five"), ("attack", "Attack"), ("shell", "Remote shell"), ("respond", "Respond")]
layout_btns = "".join(f'<button data-layout="{k}" title="Layout: {v} (key {i})">{v}</button>' for i, (k, v) in enumerate(LAYOUTS, 1))

FONTS = '<style>@font-face{font-family:"Red Hat Display";font-weight:400;font-style:normal;font-display:block;src:url("fonts/RedHatDisplay-Regular.otf") format("opentype"),local("Red Hat Display")}@font-face{font-family:"Red Hat Display";font-weight:500;font-style:normal;font-display:block;src:url("fonts/RedHatDisplay-Medium.otf") format("opentype"),local("Red Hat Display")}@font-face{font-family:"Red Hat Display";font-weight:700;font-style:normal;font-display:block;src:url("fonts/RedHatDisplay-Bold.otf") format("opentype"),local("Red Hat Display")}@font-face{font-family:"Red Hat Display";font-weight:900;font-style:normal;font-display:block;src:url("fonts/RedHatDisplay-Black.otf") format("opentype"),local("Red Hat Display")}@font-face{font-family:"Red Hat Text";font-weight:400;font-style:normal;font-display:block;src:url("fonts/RedHatText-Regular.otf") format("opentype"),local("Red Hat Text")}@font-face{font-family:"Red Hat Text";font-weight:500;font-style:normal;font-display:block;src:url("fonts/RedHatText-Medium.otf") format("opentype"),local("Red Hat Text")}@font-face{font-family:"Red Hat Text";font-weight:700;font-style:normal;font-display:block;src:url("fonts/RedHatText-Bold.otf") format("opentype"),local("Red Hat Text")}@font-face{font-family:"Red Hat Mono";font-weight:400;font-style:normal;font-display:block;src:url("fonts/RedHatMono-Regular.otf") format("opentype"),local("Red Hat Mono")}@font-face{font-family:"Red Hat Mono";font-weight:600;font-style:normal;font-display:block;src:url("fonts/RedHatMono-SemiBold.otf") format("opentype"),local("Red Hat Mono")}</style>'

CSS = r'''
:root{--bg:#f6f5f2;--panel:#fff;--side:#fbfaf8;--ink:#151515;--muted:#5e6168;--line:#e2dfd9;--accent:#ee0000;--accent-ink:#fff;--soft:#fdeceb;--code:#f0eee9;--key:#fff5dc;--keyline:#d99a00;--do:#eef4fb;--doline:#3b7dd8;
  --disp:"Red Hat Display","Red Hat Text",Inter,system-ui,sans-serif;--text:"Red Hat Text",Inter,-apple-system,"Segoe UI",Roboto,sans-serif;--mono:"Red Hat Mono","Adwaita Mono","DejaVu Sans Mono",ui-monospace,monospace}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#121212;--panel:#1b1b1d;--side:#171719;--ink:#ececec;--muted:#a3a3a8;--line:#323236;--accent:#ff4d4d;--accent-ink:#111;--soft:#2b1b1c;--code:#26262a;--key:#2b2513;--keyline:#c99700;--do:#16222f;--doline:#5b9cf0}}
:root[data-theme="dark"]{--bg:#121212;--panel:#1b1b1d;--side:#171719;--ink:#ececec;--muted:#a3a3a8;--line:#323236;--accent:#ff4d4d;--accent-ink:#111;--soft:#2b1b1c;--code:#26262a;--key:#2b2513;--keyline:#c99700;--do:#16222f;--doline:#5b9cf0}
*{box-sizing:border-box}
html,body{height:100%}
body{margin:0;background:var(--bg);color:var(--ink);font:17px/1.65 var(--text);display:grid;grid-template-rows:auto 1fr;grid-template-columns:290px minmax(0,1fr)}
body.presenting{overflow:hidden}
header{grid-column:1/-1;display:flex;align-items:center;gap:10px;flex-wrap:wrap;padding:10px 16px;background:var(--panel);border-bottom:1px solid var(--line);position:sticky;top:0;z-index:5}
header .brand{font:700 15px var(--disp);display:flex;gap:10px;align-items:center}
header .brand i{width:4px;height:20px;background:var(--accent);display:inline-block}
header .sp{flex:1}
button{font:inherit;font-size:14px;padding:6px 12px;border:1px solid var(--line);border-radius:8px;background:var(--bg);color:var(--ink);cursor:pointer}
button:hover{border-color:var(--muted)}
button.primary{background:var(--accent);border-color:var(--accent);color:#fff;font-weight:600}
#menu{display:none}
.tabs{display:flex;gap:2px;margin-left:18px;background:var(--code);border-radius:9px;padding:3px}
.tabs button{border:0;background:transparent;padding:5px 14px;border-radius:7px;font-weight:600;color:var(--muted)}
.tabs button[aria-selected="true"]{background:var(--panel);color:var(--ink);box-shadow:0 1px 3px rgba(0,0,0,.12)}
.ssbtn{position:relative;display:flex}
.ssbtn #present{border-radius:8px 0 0 8px}
.ssbtn .caret{border-radius:0 8px 8px 0;border-left:1px solid rgba(255,255,255,.35);padding:6px 9px}
.menu{position:absolute;right:0;top:calc(100% + 6px);background:var(--panel);border:1px solid var(--line);border-radius:10px;box-shadow:0 12px 30px rgba(0,0,0,.18);padding:6px;min-width:250px;z-index:20}
.menu button{display:block;width:100%;text-align:left;border:0;background:transparent;padding:9px 12px;border-radius:7px;font-size:14px}
.menu button:hover{background:var(--soft)}
.menu small{display:block;color:var(--muted);font-size:12px}
body.sv-on aside,body.sv-on main{display:none}
#sv{grid-column:1/-1;display:grid;grid-template-columns:220px minmax(0,1fr);grid-template-rows:minmax(0,1fr) minmax(170px,32%);height:calc(100vh - 53px)}
#sv[hidden]{display:none}
.film{grid-row:1/3;overflow:auto;padding:14px 12px 30px 8px;background:var(--side);border-right:1px solid var(--line)}
.fi{display:flex;gap:8px;align-items:flex-start;margin:0 0 14px;cursor:pointer}
.fi .no{font:600 12px var(--mono);color:var(--muted);width:18px;text-align:right;padding-top:4px;flex:none}
.fi .mini{border:3px solid transparent;border-radius:6px}
.fi:hover .mini{border-color:var(--line)}
.fi.sel .mini{border-color:var(--accent)}
.fi.sel .no{color:var(--accent)}
.canvas{display:flex;align-items:center;justify-content:center;padding:22px 28px;min-height:0;min-width:0;overflow:hidden}
.mini.big{width:900px;border-radius:6px;box-shadow:0 8px 30px rgba(0,0,0,.25);border:0}
.svnotes{border-top:1px solid var(--line);background:var(--panel);overflow:auto;padding:0 30px 24px;font-size:16.5px;line-height:1.6}
.svh{position:sticky;top:0;background:var(--panel);display:flex;gap:12px;align-items:center;padding:10px 0 8px;font:700 12px var(--text);letter-spacing:.08em;text-transform:uppercase;color:var(--muted);z-index:1}
.svh .sp{flex:1}
.svplan{color:var(--accent)}
.svname{text-transform:none;letter-spacing:0;font-weight:500}
#svbody .screens,#svbody .gallery,#svbody .slidevis,#svbody .crumb,#svbody>h2{display:none}
#svbody p{margin:.45em 0}
aside{background:var(--side);border-right:1px solid var(--line);overflow:auto;padding:12px 10px 40px;height:calc(100vh - 53px);position:sticky;top:53px}
.search{width:100%;font:inherit;font-size:14px;padding:7px 10px;border:1px solid var(--line);border-radius:8px;background:var(--panel);color:var(--ink);margin-bottom:8px}
.grp{margin:10px 0 6px}
.gt{font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);padding:4px 10px}
aside a{display:flex;gap:8px;align-items:baseline;padding:6px 10px;border-radius:7px;color:var(--ink);text-decoration:none;font-size:14.5px;line-height:1.35}
aside a:hover{background:var(--soft)}
aside a.on{background:var(--accent);color:#fff}
aside a.on .tm{color:inherit;opacity:.85}
aside a.hide{display:none}
.tm{font:12px var(--mono);color:var(--muted);min-width:3.6ch}
main{overflow:auto;padding:28px 40px 60px}
.page{max-width:880px;margin:0 auto}
.crumb{font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);display:flex;gap:10px;align-items:center}
.pill{background:var(--soft);color:var(--accent);border-radius:999px;padding:2px 10px;letter-spacing:0;font-size:13px}
h2{font:700 1.9rem/1.2 var(--disp);margin:.3rem 0 1.2rem}
h3{font:700 1.15rem/1.3 var(--disp);margin:1.8rem 0 .6rem}
a{color:var(--accent)}
p{margin:.7rem 0}
blockquote{margin:1rem 0;padding:.8rem 1.1rem;border-left:4px solid var(--line);background:var(--panel);border-radius:0 8px 8px 0}
blockquote.key{border-left-color:var(--keyline);background:var(--key);font-size:1.05em}
.do{display:flex;gap:10px;align-items:flex-start;margin:1rem 0;padding:.55rem .9rem;background:var(--do);border-left:4px solid var(--doline);border-radius:0 8px 8px 0;font-size:.92em}
.do .tag{font:700 11px/1.9 var(--mono);color:var(--doline);letter-spacing:.06em}
code{background:var(--code);padding:.1rem .35rem;border-radius:4px;font-size:.87em;font-family:var(--mono)}
pre{background:var(--code);padding:12px 14px;border-radius:8px;overflow:auto}
pre code{background:none;padding:0}
kbd{font:600 .85em var(--mono);border:1px solid var(--line);border-bottom-width:2px;border-radius:5px;padding:0 .35em;background:var(--panel)}
.tw{overflow-x:auto;margin:1rem 0;border:1px solid var(--line);border-radius:8px}
table{border-collapse:collapse;width:100%;font-size:.92rem;background:var(--panel)}
th,td{border-bottom:1px solid var(--line);padding:.55rem .7rem;text-align:left;vertical-align:top}
tr:last-child td{border-bottom:0}
th{background:var(--code);font-size:.85rem}
li{margin:.25rem 0}
li.cb{list-style:none;margin-left:-1.3rem}
li.cb label{display:flex;gap:.55rem;align-items:flex-start;cursor:pointer}
li.cb input{margin-top:.35rem;transform:scale(1.2);accent-color:var(--accent)}
li.cb input:checked+span{color:var(--muted);text-decoration:line-through}
.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:12px;margin:1rem 0}
figure{margin:0;background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:6px}
figure img{width:100%;display:block;border-radius:4px;cursor:zoom-in}
figcaption{font-size:.8rem;color:var(--muted);padding:4px 2px 0;line-height:1.35}
.screens{margin-top:2.5rem;padding-top:.5rem;border-top:1px dashed var(--line)}
.slidevis{margin:0 0 1.4rem;border-radius:12px;overflow:hidden;background:#0f0f0f;color:#fff;border:1px solid var(--line)}
.slidevis img{display:block;width:100%}
.slidevis.big{display:flex;align-items:center;justify-content:center;aspect-ratio:16/7;font:700 clamp(24px,4vw,52px)/1.2 var(--disp);text-align:center;padding:20px}
.slidevis.words{display:flex;flex-wrap:wrap;gap:10px;justify-content:center;align-items:center;aspect-ratio:16/6;padding:20px}
.slidevis.words span{font:600 clamp(16px,2.2vw,30px)/1 var(--disp);padding:14px 18px;border:1px solid #333;border-radius:10px;background:#1a1a1a}
.pager{max-width:880px;margin:2.5rem auto 0;display:flex;gap:12px}
.pager button{flex:1;text-align:left;padding:12px 14px}
.pager button.next{text-align:right}
.pager small{display:block;color:var(--muted);font-size:12px}
.pager button:disabled{visibility:hidden}
.hint{max-width:880px;margin:14px auto 0;font-size:12px;color:var(--muted);text-align:center}
#zoom{position:fixed;inset:0;background:rgba(0,0,0,.88);display:none;align-items:center;justify-content:center;z-index:90;cursor:zoom-out;padding:16px}
#zoom img{max-width:100%;max-height:100%}

/* ---------------------------------------------------------------- deck (audience) */
#deck{position:fixed;inset:0;z-index:50;background:#000;cursor:default;color-scheme:dark}
#deck[hidden]{display:none}
#deck.idle .stage{cursor:none}
.stage{position:absolute;left:50%;top:50%;width:1920px;height:1080px;transform:translate(-50%,-50%) scale(var(--k,.5));transform-origin:center;background:#151515;color:#fff;overflow:hidden;font-family:var(--text)}
.slide{position:absolute;inset:0;padding:110px 150px 130px;display:none;flex-direction:column;justify-content:center}
.slide.on{display:flex}
.slide .kicker{font:700 28px/1 var(--disp);letter-spacing:.14em;text-transform:uppercase;color:#ee0000;margin-bottom:34px}
.slide h1{font:900 150px/1.02 var(--disp);margin:0 0 40px;letter-spacing:-.02em}
.slide h2{font:700 84px/1.08 var(--disp);margin:0 0 60px;letter-spacing:-.01em;color:#fff}
.slide .lead{font:400 54px/1.3 var(--text);color:#d2d2d2;margin:0}
.slide .byline{position:absolute;left:150px;bottom:90px;font:500 28px var(--text);color:#a3a3a3}
.slide em{font-style:normal;color:#ee0000}
.slide .rbar{position:absolute;left:0;top:0;bottom:0;width:22px;background:#ee0000}
.slide .foot{position:absolute;left:150px;right:150px;bottom:54px;display:flex;justify-content:space-between;font:500 22px var(--text);color:#a3a3a3;border-top:2px solid #383838;padding-top:20px;align-items:center}
.slide.title{padding-left:190px}
.slide.title .byline{left:190px}
.slide.statement .big{font:900 128px/1.08 var(--disp);margin:0 0 60px;max-width:1500px;letter-spacing:-.02em}
.slide.shotslide{justify-content:flex-start}
.slide.shotslide h2{margin-bottom:36px}
.slide .shot{display:block;height:620px;width:auto;max-width:100%;border-radius:18px;border:2px solid #2a2a2a;box-shadow:0 30px 80px rgba(0,0,0,.6);align-self:center}
.slide .f{opacity:0;transform:translateY(24px);transition:opacity .35s ease,transform .35s ease}
.slide .f.on{opacity:1;transform:none}
.cols{display:grid;grid-template-columns:repeat(3,1fr);gap:44px}
.card{background:#1f1f1f;border-top:6px solid #ee0000;border-radius:6px;padding:44px 42px 48px}
.card .n{font:900 64px/1 var(--disp);color:#ee0000;margin-bottom:26px}
.card h3{font:700 46px/1.15 var(--disp);margin:0 0 22px;color:#fff}
.card p{font:400 34px/1.4 var(--text);color:#c9c9c9;margin:0}
.slide.statement .lead+.lead{margin-top:24px}
.slide .ico{fill:currentColor;display:block;flex:none}
.card .ico{width:84px;height:84px;color:#ee0000;margin-bottom:28px}
.word .ico{width:72px;height:72px;color:#c7c7c7;margin-bottom:24px}
.word.act .ico{color:#ee0000}
.recap .ico{width:60px;height:60px;color:#ee0000}
.ticks.icons li{padding-left:96px}
.ticks.icons li::before{display:none}
.ticks.icons .ico{position:absolute;left:0;top:-.02em;width:66px;height:66px;color:#ee0000}
.slide .lead.withico{display:flex;align-items:center;gap:30px}
.slide .lead.withico .ico{width:76px;height:76px;color:#ee0000}
.slide .rhlogo{position:absolute;right:150px;bottom:84px;height:56px;width:auto}
.slide .note{font:500 40px var(--text);color:#d2d2d2;margin:60px 0 0}
.ticks{list-style:none;margin:0 0 60px;padding:0}
.ticks li{font:400 50px/1.35 var(--text);color:#e6e6e6;margin:0 0 26px;padding-left:76px;position:relative}
.ticks li::before{content:"";position:absolute;left:0;top:.42em;width:40px;height:22px;border-left:7px solid #ee0000;border-bottom:7px solid #ee0000;transform:rotate(-45deg)}
.punch{font:700 64px/1.2 var(--disp);margin:0}
.words{display:grid;grid-template-columns:repeat(5,1fr);gap:26px}
.word{background:#1f1f1f;border-radius:6px;padding:40px 30px 44px;border-top:6px solid #4d4d4d}
.word h3{font:700 50px/1.1 var(--disp);margin:0 0 22px;color:#fff}
.word p{font:400 32px/1.5 var(--text);color:#bdbdbd;margin:0}
.word.act{border-top-color:#ee0000;background:#3f0000}
.word.act h3{color:#ee0000}
.recap{display:flex;flex-direction:column;gap:18px}
.recap .row{display:grid;grid-template-columns:72px 300px 1fr;gap:0 28px;align-items:center;background:#1f1f1f;border-left:8px solid #ee0000;border-radius:6px;padding:26px 40px}
.recap b{font:700 46px var(--disp);color:#fff}
.recap span{font:400 42px var(--text);color:#d6d6d6}
.qs{margin:0;padding:0;list-style:none;counter-reset:q}
.qs li{counter-increment:q;font:500 56px/1.3 var(--text);color:#f0f0f0;margin:0 0 46px;padding-left:120px;position:relative}
.qs li::before{content:counter(q);position:absolute;left:0;top:-4px;font:900 80px/1 var(--disp);color:#ee0000}
.termph{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:#0b0b0b}
.termph span{font:700 70px var(--disp);color:#555}
#black{position:absolute;inset:0;background:#000;z-index:20}
#black[hidden]{display:none}
.dctl{position:absolute;left:50%;bottom:18px;transform:translateX(-50%);display:flex;gap:8px;align-items:center;background:rgba(20,20,20,.92);border:1px solid #333;border-radius:12px;padding:8px 10px;color:#ddd;font:14px var(--text);opacity:0;transition:opacity .25s;z-index:30}
#deck.show-ctl .dctl,.dctl:hover{opacity:1}
.dctl button,.tbar button{background:#262626;border-color:#3a3a3a;color:#eee}
.dctl button:hover,.tbar button:hover{border-color:#777}
.dctl .clk,.tbar .clk{font:600 16px var(--mono);min-width:4.6ch;text-align:right;color:#fff}
.dctl .num{font:13px var(--mono);color:#aaa;padding:0 6px}

/* live terminals slide */
#terms{position:absolute;inset:0;z-index:10;background:#0b0b0b;display:flex;flex-direction:column}
#terms[hidden]{display:none}
.tbar{height:54px;flex:none;display:flex;align-items:center;gap:12px;padding:0 16px;background:#151515;border-bottom:4px solid #ee0000;color:#fff}
.tbar .ttl{font:700 19px var(--disp);display:flex;gap:12px;align-items:center}
.tbar .ttl::before{content:"";width:4px;height:22px;background:#ee0000}
.tbar .sp{flex:1}
.tbar .tip{font:13px var(--text);color:#9a9a9a}
.tgrid{flex:1;min-height:0;position:relative;overflow:hidden;margin:4px}
.tp{position:absolute;display:flex;flex-direction:column;min-height:0;border-radius:8px;overflow:hidden;background:var(--bgc);border:1px solid #333;transition:left .25s,top .25s,width .25s,height .25s,opacity .2s}
.tp.src{opacity:.55}
.split{position:absolute;z-index:40;touch-action:none}
.split.v{width:12px;margin-left:-6px;cursor:col-resize}
.split.h{height:12px;margin-top:-6px;cursor:row-resize}
.split::after{content:"";position:absolute;background:transparent;border-radius:2px;transition:background .15s}
.split.v::after{left:5px;width:2px;top:8px;bottom:8px}
.split.h::after{top:5px;height:2px;left:8px;right:8px}
.split:hover::after,.split.on::after{background:#ee0000}
#drop{position:absolute;z-index:60;border:3px solid #ee0000;background:rgba(238,0,0,.16);border-radius:8px;pointer-events:none;transition:left .08s,top .08s,width .08s,height .08s}
#drop[hidden]{display:none}
.th .wb button.wrst.arm{background:#ee0000;border-color:#ee0000;color:#fff;width:auto;padding:0 8px;font-size:12px}
.tp.front{border-color:#666}
.tgrid.dragging .tp{transition:none}
.tgrid.dragging iframe{pointer-events:none}
.tp.min{opacity:0;visibility:hidden;pointer-events:none}
.tp.maxed{left:4px!important;top:4px!important;width:calc(100% - 8px)!important;height:calc(100% - 8px)!important;z-index:900!important}
.th{flex:none;display:flex;align-items:center;gap:10px;padding:6px 8px 6px 14px;background:rgba(255,255,255,.07);border-bottom:1px solid rgba(255,255,255,.08);color:#fff;white-space:nowrap;overflow:hidden;cursor:grab;user-select:none;touch-action:none}
.tgrid.dragging .th{cursor:grabbing}
.th .wb{margin-left:auto;display:flex;gap:6px;flex:none}
.th .wb button{background:rgba(0,0,0,.25);border:1px solid rgba(255,255,255,.18);color:#eee;width:30px;height:26px;padding:0;font-size:15px;line-height:1;border-radius:6px;cursor:pointer}
.th .wb button:hover{background:rgba(255,255,255,.15)}
.th .wb button.wfm,.th .wb button.wfp{width:34px;font:700 12px var(--text)}
.tdock{flex:none;height:44px;display:flex;align-items:center;gap:8px;padding:0 12px;background:#151515;border-top:1px solid #2a2a2a;color:#888;font:13px var(--text);overflow-x:auto}
.tdock .dl{flex:none}
.tdock button{display:flex;align-items:center;gap:8px;background:#222;border:1px solid #3a3a3a;color:#eee;font:600 13px var(--text);padding:5px 12px;border-radius:7px;white-space:nowrap}
.tdock button i{width:9px;height:9px;border-radius:50%;background:var(--dot)}
.tdock:not(.has){display:none}
.lays,.slays{display:flex;gap:6px;flex-wrap:wrap}
.lays button{font-size:13px;padding:5px 11px}
.lays button.on,.slays button.on{background:#ee0000;border-color:#ee0000;color:#fff}
.slays button{background:#262626;border-color:#3a3a3a;color:#eee;font-size:13px}
.th .dot{width:11px;height:11px;border-radius:50%;background:var(--dot);flex:none}
.th b{font:700 16px var(--disp)}
.th small{font:13px var(--mono);color:#bdbdbd;overflow:hidden;text-overflow:ellipsis}
.tb{flex:1;min-height:0;position:relative}
.tb iframe{position:absolute;inset:0;width:100%;height:100%;border:0;background:var(--bgc)}
.term-off{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;color:#d0d0d0;font:15px var(--text);text-align:center;padding:16px}
.term-off code{background:rgba(0,0,0,.35);color:#fff;font-size:15px;padding:.3em .6em}
.term-off button{background:#262626;border-color:#3a3a3a;color:#eee}

/* ---------------------------------------------------------------- speaker view */
#spk{color-scheme:dark;position:fixed;inset:0;z-index:60;background:#0f0f0f;color:#eee;display:grid;grid-template-columns:minmax(0,1.35fr) minmax(340px,1fr);grid-template-rows:auto 1fr;font-family:var(--text)}
#spk[hidden]{display:none}
.sbar{grid-column:1/-1;display:flex;align-items:center;gap:12px;padding:10px 18px;background:#151515;border-bottom:4px solid #ee0000;flex-wrap:wrap}
.sbar .ttl{font:700 16px var(--disp);letter-spacing:.06em;text-transform:uppercase;color:#bbb}
.sbar .sp{flex:1}
.sbar .clk{font:700 34px/1 var(--mono);color:#fff}
.sbar .clk.late{color:#ff4d4d}
.sbar .plan{font:600 15px var(--mono);color:#aaa}
.sbar .num{font:14px var(--mono);color:#aaa}
.sbar .link{font:13px var(--text);color:#8a8a8a}
.sbar .link.ok{color:#3fb950}
.sbar button{background:#262626;border-color:#3a3a3a;color:#eee}
.snotes{overflow:auto;padding:26px 34px 60px;font-size:var(--nf,23px);line-height:1.55;background:#141414}
.snotes .nh{display:flex;align-items:center;gap:12px;margin-bottom:6px;color:#999;font:700 13px var(--text);letter-spacing:.08em;text-transform:uppercase}
.snotes .nh button{background:#262626;border-color:#3a3a3a;color:#eee;font-size:13px;padding:3px 10px;letter-spacing:0;text-transform:none}
.snotes h2{color:#fff;font-size:1.5em;margin:.2rem 0 1rem}
.snotes p{margin:.55em 0}
.snotes .do{background:#13202e;color:#cfe3ff;border-left-color:#5b9cf0;font-size:.78em}
.snotes .do .tag{color:#5b9cf0}
.snotes blockquote.key{background:#2b2513;border-left-color:#c99700;color:#fff}
.snotes code{background:#262626;color:#fff}
.snotes .screens,.snotes .gallery,.snotes .slidevis,.snotes .crumb{display:none}
.snotes table{font-size:.7em;background:#1b1b1b;color:#ddd}
.snotes th{background:#262626}
.snotes td,.snotes th{border-color:#333}
.sside{overflow:auto;padding:18px;display:flex;flex-direction:column;gap:14px;border-left:1px solid #262626}
.sside .lbl{font:700 12px var(--text);letter-spacing:.1em;text-transform:uppercase;color:#888}
.mini{position:relative;width:100%;aspect-ratio:16/9;overflow:hidden;border-radius:8px;border:1px solid #333;background:#000}
.mini .stage{--k:.2}
.mini.next{opacity:.8;cursor:pointer}
.mini.next:hover{opacity:1;outline:3px solid #ee0000}
#mcur{cursor:pointer}
.sstrip{display:grid;grid-template-columns:repeat(6,1fr);gap:6px}
.sstrip .st{position:relative;cursor:pointer}
.sstrip .st .mini{border:2px solid #333}
.sstrip .st.on .mini{border-color:#ee0000}
.sstrip .st b{position:absolute;left:4px;top:2px;font:700 11px var(--mono);color:#fff;text-shadow:0 0 3px #000;z-index:2}
.mini .slide .f{transition:none}
.skeys{font:13px/1.7 var(--text);color:#888}
@media (max-width:900px){
  body{grid-template-columns:1fr}
  #menu{display:inline-block}
  aside{position:fixed;top:53px;left:0;bottom:0;width:min(320px,88vw);height:auto;z-index:6;transform:translateX(-100%);transition:transform .2s;box-shadow:0 0 30px rgba(0,0,0,.25)}
  body.nav-open aside{transform:none}
  main{padding:20px 16px 50px}
  h2{font-size:1.5rem}
  #spk{grid-template-columns:1fr;grid-template-rows:auto auto 1fr}
  .sside{order:-1;border-left:0;flex-direction:row;overflow-x:auto}
  .sside>div{min-width:260px}
}
@media print{header,aside,.pager,.hint,#deck,#spk{display:none}body{display:block}main{overflow:visible;padding:0}.page[hidden]{display:block!important}.page{break-after:page}}
'''

JS = r'''
(function(){
  const S={get(k){try{return localStorage.getItem(k)}catch(e){return null}},set(k,v){try{localStorage.setItem(k,v)}catch(e){}}};
  const Q=new URLSearchParams(location.search), root=document.documentElement, body=document.body;
  const $=id=>document.getElementById(id);
  const th=S.get('talk-theme'); if(th) root.dataset.theme=th;

  // ------------------------------------------------------------ handbook pages
  const pages=[...document.querySelectorAll('.page')], links=[...document.querySelectorAll('aside a')];
  const prev=$('prev'), next=$('next');
  const byId=id=>pages.findIndex(p=>p.id===id);
  let cur=0;
  function show(i){
    i=Math.max(0,Math.min(pages.length-1,i)); cur=i;
    pages.forEach((p,j)=>p.hidden=j!==i);
    links.forEach(a=>a.classList.toggle('on',a.dataset.id===pages[i].id));
    const on=links.find(a=>a.dataset.id===pages[i].id); if(on) on.scrollIntoView({block:'nearest'});
    const t=p=>p.querySelector('h2').textContent;
    prev.disabled=i===0; next.disabled=i===pages.length-1;
    if(i>0) prev.innerHTML='<small>← Previous</small>'+esc(t(pages[i-1]));
    if(i<pages.length-1) next.innerHTML='<small>Next →</small>'+esc(t(pages[i+1]));
    document.querySelector('main').scrollTop=0;
    if($('sv').hidden && location.hash!=='#'+pages[i].id) history.replaceState(null,'','#'+pages[i].id);
    S.set('talk-page',pages[i].id); body.classList.remove('nav-open');
  }
  function esc(s){return s.replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
  links.forEach(a=>a.addEventListener('click',e=>{e.preventDefault();show(byId(a.dataset.id))}));
  prev.onclick=()=>show(cur-1); next.onclick=()=>show(cur+1);
  addEventListener('hashchange',()=>{const h=/^#slide-(\d+)$/.exec(location.hash); if(h){ if($('sv').hidden) view('slides'); select(+h[1]-1,true); return }
    const i=byId(location.hash.slice(1)); if(i>=0){ if(!$('sv').hidden) view('guide'); show(i) }});
  document.querySelectorAll('main a[href^="#"]').forEach(a=>a.addEventListener('click',e=>{const i=byId(a.getAttribute('href').slice(1)); if(i>=0){e.preventDefault();show(i)}}));
  const q=$('q');
  q.addEventListener('input',()=>{const v=q.value.toLowerCase().trim();
    links.forEach(a=>{const p=pages[byId(a.dataset.id)]; a.classList.toggle('hide', !!v && !p.textContent.toLowerCase().includes(v))})});
  $('menu').onclick=()=>body.classList.toggle('nav-open');
  $('theme').onclick=()=>{const dark=root.dataset.theme?root.dataset.theme==='dark':matchMedia('(prefers-color-scheme: dark)').matches; root.dataset.theme=dark?'light':'dark'; S.set('talk-theme',root.dataset.theme)};
  document.querySelectorAll('main li.cb input').forEach((cb,i)=>{cb.checked=S.get('talk-cb-'+i)==='1';cb.onchange=()=>S.set('talk-cb-'+i,cb.checked?'1':'')});
  const zoom=$('zoom'), zi=zoom.querySelector('img');
  document.querySelectorAll('main figure img').forEach(im=>im.onclick=()=>{zi.src=im.src;zoom.style.display='flex'});
  zoom.onclick=()=>zoom.style.display='none';

  // ------------------------------------------------------------ shared: slides + timer
  const deck=$('deck'), stage=$('stage'), slides=[...stage.querySelectorAll('.slide')];
  const steps=s=>s.querySelectorAll('.f').length;
  const fmt=ms=>{const s=Math.max(0,Math.floor(ms/1000));return Math.floor(s/60)+':'+String(s%60).padStart(2,'0')};
  const secs=t=>{const [m,s]=t.split(':').map(Number);return (m*60+(s||0))*1000};
  const planOf=id=>{const p=pages[byId(id)];const m=p&&p.querySelector('.pill');return m?m.textContent.replace('⏱','').trim():''};
  const bc=('BroadcastChannel' in window)?new BroadcastChannel('unhackable-talk'):null;
  const SPEAKER=Q.has('speaker');

  // ------------------------------------------------------------ deck (audience window)
  let di=0, ds=0, tStart=null, tAcc=0, spk=null;
  const elapsed=()=>tAcc+(tStart?Date.now()-tStart:0);
  function fit(){stage.style.setProperty('--k',Math.min(innerWidth/1920,innerHeight/1080))}
  function render(){
    slides.forEach((s,j)=>s.classList.toggle('on',j===di));
    slides[di].querySelectorAll('.f').forEach((f,j)=>f.classList.toggle('on',j<ds));
    const term=slides[di].classList.contains('term');
    $('terms').hidden=!term; if(term) mountTerms();
    S.set('talk-slide',di); send();
  }
  function go(d){
    if(d>0){ if(ds<steps(slides[di])) ds++; else if(di<slides.length-1){di++;ds=0} }
    else { if(ds>0) ds--; else if(di>0){di--;ds=steps(slides[di])} }
    render();
  }
  function to(i,st){di=Math.max(0,Math.min(slides.length-1,i|0)); ds=Math.max(0,Math.min(st|0,steps(slides[di]))); render()}
  function openDeck(i){
    deck.hidden=false; body.classList.add('presenting'); fit();
    if(i!=null) to(i,0); else render();
  }
  function closeDeck(){
    deck.hidden=true; body.classList.remove('presenting'); $('black').hidden=true;
    try{if(document.fullscreenElement){ fsByKey=true; document.exitFullscreen().catch(()=>{}) }}catch(e){}
    send();
  }
  let fsByKey=false;
  function toggleFS(){fsByKey=true;try{document.fullscreenElement?document.exitFullscreen():document.documentElement.requestFullscreen()}catch(e){}}
  document.addEventListener('fullscreenchange',()=>{ fsByKey=false; if(!deck.hidden) fit() });
  function toggleTimer(){ if(tStart){tAcc+=Date.now()-tStart;tStart=null}else tStart=Date.now(); tickDeck(); send() }
  function resetTimer(){ tAcc=0; if(tStart) tStart=Date.now(); tickDeck(); send() }
  function toggleBlack(){ $('black').hidden=!$('black').hidden; send() }
  function tickDeck(){ const t=fmt(elapsed()); document.querySelectorAll('.dclk').forEach(c=>c.textContent=t) }
  function openSpeaker(){
    spk=window.open(location.href.split(/[?#]/)[0]+'?speaker','unhackable-speaker','width=1360,height=860');
    setTimeout(send,400); setTimeout(send,1200);
  }
  function send(){
    const m={t:'state',i:di,step:ds,open:!deck.hidden,el:elapsed(),run:!!tStart,black:!$('black').hidden,layout:curLayout};
    try{ if(spk && !spk.closed) spk.postMessage(m,'*') }catch(e){}
    try{ bc && bc.postMessage(m) }catch(e){}
  }
  function onCmd(m){
    if(!m||typeof m.t!=='string') return;
    if(m.t==='go'){ if(deck.hidden) openDeck(); go(m.d>0?1:-1) }
    else if(m.t==='to'){ if(deck.hidden) openDeck(); to(m.i,m.step) }
    else if(m.t==='timer') toggleTimer();
    else if(m.t==='reset') resetTimer();
    else if(m.t==='black') toggleBlack();
    else if(m.t==='hello') send();
    else if(m.t==='layout' && LAY[m.name]){ if(deck.hidden) openDeck(); layout(m.name) }
    else if(m.t==='restart-all') restartAll();
    else if(m.t==='font' && (m.d===2||m.d===-2)) fontAll(m.d);
  }
  // live terminals
  const TH=/^[\w.-]+$/.test(Q.get('termhost')||'')?Q.get('termhost'):'127.0.0.1';
  let termsMounted=false;
  function mountTerms(){ if(termsMounted) return; termsMounted=true; document.querySelectorAll('#terms .tp').forEach(mountPanel) }
  function mountPanel(tp,reset){
    const url='http://'+TH+':'+tp.dataset.port+'/', box=tp.querySelector('.tb');
    box.innerHTML='<div class="term-off">Connecting…</div>';
    fetch(url,{mode:'no-cors',cache:'no-store'}).then(()=>{
      box.innerHTML=''; const f=document.createElement('iframe'); const q=new URLSearchParams();
      const fs=+(S.get('talk-fs-'+tp.dataset.name)||tp.dataset.fs); if(fs!==+tp.dataset.fs) q.set('fontSize',fs);
      if(reset) q.set('arg','reset'); f.src=url+(q.toString()?'?'+q:''); f.title=tp.dataset.label; box.appendChild(f);
    }).catch(()=>{
      box.innerHTML='<div class="term-off"><b>Not running</b><div>Start the browser terminals:</div><code>make web-terminal</code><button type="button">Try again</button></div>';
      box.querySelector('button').onclick=()=>mountPanel(tp);
    });
  }
  // terminal windows: TILING — they always fill the screen and share borders ("magnets").
  // Model: columns of rows. Drag a border to resize both sides; drag a title onto another window
  // to swap (centre) or dock beside it (edge); minimize and the others fill the space.
  const ws=$('ws'), dock=$('dock'), drop=$('drop'), panes=[...ws.querySelectorAll('.tp')];
  const P=n=>panes.find(p=>p.dataset.name===n);
  const C=(w,...rows)=>({w,rows:rows.map(([n,h])=>({n,h}))});
  const LAY={
    all:    ()=>[C(.53,['attacker',.62],['c2',.38]), C(.47,['rhacs',.5],['blog',.27],['pods',.23])],
    attack: ()=>[C(.56,['attacker',1]), C(.44,['rhacs',1])],
    shell:  ()=>[C(.56,['attacker',.56],['c2',.44]), C(.44,['rhacs',1])],
    respond:()=>[C(.5,['attacker',.58],['c2',.42]), C(.5,['rhacs',.58],['pods',.42])]
  };
  let M={cols:LAY.all(), last:{}}, curLayout='all';
  const pct=v=>(v*100).toFixed(3)+'%';
  function place(tp,r){ tp._r=r; tp.style.left='calc('+pct(r[0])+' + 4px)'; tp.style.top='calc('+pct(r[1])+' + 4px)';
    tp.style.width='calc('+pct(r[2])+' - 8px)'; tp.style.height='calc('+pct(r[3])+' - 8px)'; }
  function norm(){
    M.cols=M.cols.filter(c=>c.rows.length);
    const tw=M.cols.reduce((a,c)=>a+c.w,0)||1;
    M.cols.forEach(c=>{ c.w/=tw; const th=c.rows.reduce((a,r)=>a+r.h,0)||1; c.rows.forEach(r=>r.h/=th) });
  }
  function find(n){ for(let ci=0;ci<M.cols.length;ci++){ const ri=M.cols[ci].rows.findIndex(r=>r.n===n); if(ri>=0) return [ci,ri] } return null }
  function tile(){
    norm(); ws.querySelectorAll('.split').forEach(x=>x.remove());
    const shown=new Set(); let x=0;
    M.cols.forEach((c,ci)=>{
      let y=0;
      c.rows.forEach((r,ri)=>{ const tp=P(r.n); if(!tp) return; shown.add(r.n); place(tp,[x,y,c.w,r.h]); tp.classList.remove('min');
        if(ri>0) splitter('h',ci,ri,{left:'calc('+pct(x)+' + 4px)',width:'calc('+pct(c.w)+' - 8px)',top:pct(y)});
        y+=r.h });
      if(ci>0) splitter('v',ci,0,{left:pct(x),top:'4px',bottom:'4px'});
      x+=c.w;
    });
    panes.forEach(p=>{ if(!shown.has(p.dataset.name)){ p.classList.add('min'); p.classList.remove('maxed') } });
    renderDock(); saveWM(); send();
  }
  function splitter(kind,ci,ri,css){
    const d=document.createElement('div'); d.className='split '+kind; Object.assign(d.style,css); ws.appendChild(d);
    d.addEventListener('pointerdown',e=>{
      if(e.button!==0) return; e.preventDefault(); custom(); d.setPointerCapture(e.pointerId); ws.classList.add('dragging'); d.classList.add('on');
      const W=ws.clientWidth, H=ws.clientHeight, x0=e.clientX, y0=e.clientY;
      const A=kind==='v'?M.cols[ci-1]:M.cols[ci].rows[ri-1], B=kind==='v'?M.cols[ci]:M.cols[ci].rows[ri], key=kind==='v'?'w':'h';
      const a0=A[key], b0=B[key], min=kind==='v'?260/W:110/H;
      const mv=ev=>{ let dlt=kind==='v'?(ev.clientX-x0)/W:(ev.clientY-y0)/H; dlt=Math.max(min-a0,Math.min(b0-min,dlt)); A[key]=a0+dlt; B[key]=b0-dlt; layoutOnly({el:d,kind,ci,ri}) };
      const up=()=>{ ws.classList.remove('dragging'); d.classList.remove('on'); d.removeEventListener('pointermove',mv); d.removeEventListener('pointerup',up); d.removeEventListener('pointercancel',up); tile() };
      d.addEventListener('pointermove',mv); d.addEventListener('pointerup',up); d.addEventListener('pointercancel',up);
    });
  }
  function layoutOnly(act){ // live resize: move windows + borders; the dragged border element is kept
    let x=0;
    M.cols.forEach(c=>{ let y=0; c.rows.forEach(r=>{ place(P(r.n),[x,y,c.w,r.h]); y+=r.h }); x+=c.w });
    // draw guide lines where the borders are now (the real splitters come back on release)
    ws.querySelectorAll('.split').forEach(x=>{ if(x!==act.el) x.remove() }); let xx=0;
    const put=(kind,ci,ri,css)=>{ if(kind===act.kind&&ci===act.ci&&ri===act.ri) Object.assign(act.el.style,css); else ghostSplit(kind,css) };
    M.cols.forEach((c,ci)=>{ let y=0; c.rows.forEach((r,ri)=>{ if(ri>0) put('h',ci,ri,{left:'calc('+pct(xx)+' + 4px)',width:'calc('+pct(c.w)+' - 8px)',top:pct(y)}); y+=r.h }); if(ci>0) put('v',ci,0,{left:pct(xx),top:'4px',bottom:'4px'}); xx+=c.w });
  }
  function ghostSplit(kind,css){ const d=document.createElement('div'); d.className='split '+kind+' on'; d.style.pointerEvents='none'; Object.assign(d.style,css); ws.appendChild(d) }
  function removeFromModel(n){ const f=find(n); if(!f) return; M.last[n]=f[0]; M.cols[f[0]].rows.splice(f[1],1); norm() }
  function setMin(tp,on){
    const n=tp.dataset.name; custom();
    if(on){ removeFromModel(n) }
    else if(!find(n)){ if(!M.cols.length) M.cols.push({w:1,rows:[]}); const c=M.cols[Math.min(M.last[n]??M.cols.length-1, M.cols.length-1)]; c.rows.push({n,h:1/Math.max(1,c.rows.length)}) }
    tile();
  }
  function setMax(tp,on){ panes.forEach(p=>{ p.classList.toggle('maxed',on&&p===tp); p.querySelector('.wmax').textContent=(on&&p===tp)?'❐':'□' }); saveWM() }
  function renderDock(){
    dock.querySelectorAll('button').forEach(b=>b.remove());
    const mins=panes.filter(p=>!find(p.dataset.name)); dock.classList.toggle('has',mins.length>0);
    mins.forEach(p=>{ const b=document.createElement('button'); b.style.setProperty('--dot',getComputedStyle(p).getPropertyValue('--dot'));
      b.innerHTML='<i></i>'; b.appendChild(document.createTextNode(p.dataset.label)); b.title='Restore';
      b.onclick=()=>setMin(p,false); dock.appendChild(b) });
  }
  function layout(name){
    if(!LAY[name]) return; M.cols=LAY[name](); setMax(panes[0],false); curLayout=name;
    document.querySelectorAll('[data-layout]').forEach(b=>b.classList.toggle('on',b.dataset.layout===name)); tile();
  }
  function custom(){ curLayout=''; document.querySelectorAll('[data-layout]').forEach(b=>b.classList.remove('on')) }
  function saveWM(){ S.set('talk-tiles',JSON.stringify({l:curLayout,m:M,max:(panes.find(p=>p.classList.contains('maxed'))||{}).dataset?.name||''})) }
  function loadWM(){
    try{ const w=JSON.parse(S.get('talk-tiles')||'null');
      if(w && w.m && Array.isArray(w.m.cols) && w.m.cols.every(c=>Array.isArray(c.rows) && c.rows.every(r=>P(r.n)))){
        M={cols:w.m.cols,last:w.m.last||{}}; curLayout=w.l||''; document.querySelectorAll('[data-layout]').forEach(b=>b.classList.toggle('on',b.dataset.layout===curLayout)); tile();
        if(w.max&&P(w.max)) setMax(P(w.max),true); return }
    }catch(e){}
    layout('all');
  }
  // move: drag a title bar onto another window
  function zoneAt(cx,cy,src){
    const wr=ws.getBoundingClientRect();
    for(const tp of panes){ if(tp===src||!find(tp.dataset.name)) continue; const r=tp.getBoundingClientRect();
      if(cx<r.left||cx>r.right||cy<r.top||cy>r.bottom) continue;
      const fx=(cx-r.left)/r.width, fy=(cy-r.top)/r.height, ed=Math.min(fx,1-fx,fy,1-fy);
      let z='center'; if(ed<.28){ z=ed===fx?'left':ed===1-fx?'right':ed===fy?'top':'bottom' }
      let L=r.left-wr.left, T=r.top-wr.top, Wd=r.width, Ht=r.height;
      if(z==='left') Wd/=2; else if(z==='right'){L+=Wd/2;Wd/=2} else if(z==='top') Ht/=2; else if(z==='bottom'){T+=Ht/2;Ht/=2}
      return {tp,z,box:[L,T,Wd,Ht]};
    }
    return null;
  }
  function moveTo(src,t){
    const s=src.dataset.name, d=t.tp.dataset.name;
    if(t.z==='center'){ const a=find(s), b=find(d); M.cols[a[0]].rows[a[1]].n=d; M.cols[b[0]].rows[b[1]].n=s; return tile() }
    removeFromModel(s); const [ci,ri]=find(d), col=M.cols[ci], tr=col.rows[ri];
    if(t.z==='top'||t.z==='bottom'){ const h=tr.h/2; tr.h=h; col.rows.splice(t.z==='top'?ri:ri+1,0,{n:s,h}) }
    else { const w=col.w/2; col.w=w; M.cols.splice(t.z==='left'?ci:ci+1,0,{w,rows:[{n:s,h:1}]}) }
    tile();
  }
  panes.forEach(tp=>{
    const th=tp.querySelector('.th');
    th.addEventListener('pointerdown',e=>{
      if(e.button!==0||e.target.closest('button')||tp.classList.contains('maxed')) return;
      e.preventDefault(); th.setPointerCapture(e.pointerId);
      const x0=e.clientX, y0=e.clientY; let moving=false, tgt=null;
      const mv=ev=>{
        if(!moving && Math.hypot(ev.clientX-x0,ev.clientY-y0)<8) return;
        if(!moving){ moving=true; ws.classList.add('dragging'); tp.classList.add('src') }
        tgt=zoneAt(ev.clientX,ev.clientY,tp);
        if(tgt){ drop.hidden=false; Object.assign(drop.style,{left:tgt.box[0]+'px',top:tgt.box[1]+'px',width:tgt.box[2]+'px',height:tgt.box[3]+'px'}) } else drop.hidden=true;
      };
      const up=()=>{ th.removeEventListener('pointermove',mv); th.removeEventListener('pointerup',up); th.removeEventListener('pointercancel',up);
        ws.classList.remove('dragging'); tp.classList.remove('src'); drop.hidden=true;
        if(moving&&tgt){ custom(); moveTo(tp,tgt) } };
      th.addEventListener('pointermove',mv); th.addEventListener('pointerup',up); th.addEventListener('pointercancel',up);
    });
    th.addEventListener('dblclick',e=>{ if(!e.target.closest('button')) setMax(tp,!tp.classList.contains('maxed')) });
    tp.querySelector('.wmin').onclick=()=>setMin(tp,true);
    tp.querySelector('.wmax').onclick=()=>setMax(tp,!tp.classList.contains('maxed'));
    tp.querySelector('.wfm').onclick=()=>fontStep(tp,-2); tp.querySelector('.wfp').onclick=()=>fontStep(tp,2);
    // restart from zero: two clicks (the first one arms it for 3 s)
    const rb=tp.querySelector('.wrst'); let armT=null;
    rb.onclick=()=>{ if(!rb.classList.contains('arm')){ rb.classList.add('arm'); rb.textContent='Restart?'; armT=setTimeout(()=>{rb.classList.remove('arm');rb.textContent='↻'},3000); return }
      clearTimeout(armT); rb.classList.remove('arm'); rb.textContent='↻'; mountPanel(tp,true) };
  });
  function restartAll(){ panes.forEach(tp=>mountPanel(tp,true)) }
  // text size per window: reconnects the window with ?fontSize=N — tmux keeps the same process running
  function fontStep(tp,d){ const cur=+(S.get('talk-fs-'+tp.dataset.name)||tp.dataset.fs); const n=Math.max(10,Math.min(48,cur+d));
    if(n===cur) return; S.set('talk-fs-'+tp.dataset.name,n); clearTimeout(tp._fsT); tp._fsT=setTimeout(()=>mountPanel(tp),250) }
  function fontAll(d){ panes.forEach(tp=>fontStep(tp,d)) }
  document.querySelectorAll('[data-layout]').forEach(b=>b.addEventListener('click',e=>{ e.stopPropagation();
    if(SPEAKER) cmd({t:'layout',name:b.dataset.layout}); else layout(b.dataset.layout) }));
  loadWM();

  // deck controls
  document.querySelectorAll('[data-cmd]').forEach(b=>b.addEventListener('click',e=>{e.stopPropagation();
    const c=b.dataset.cmd; if(c==='prev')go(-1); else if(c==='next')go(1); else if(c==='exit')closeDeck(); else if(c==='speaker')openSpeaker(); else if(c==='timer')toggleTimer(); else if(c==='fs')toggleFS();}));
  stage.addEventListener('click',()=>go(1));
  let idleT=null;
  deck.addEventListener('mousemove',()=>{deck.classList.remove('idle');clearTimeout(idleT);idleT=setTimeout(()=>deck.classList.add('idle'),2000)});
  addEventListener('resize',()=>{fit();fitMinis()});
  addEventListener('message',e=>{ if(!SPEAKER && spk && e.source===spk) onCmd(e.data); else if(SPEAKER) onSpk(e.data, e.source===window.opener) });
  if(bc) bc.onmessage=e=>{ if(SPEAKER) onSpk(e.data,true); else onCmd(e.data) };
  setInterval(()=>{ if(!SPEAKER){ tickDeck(); send() } },1000);
  $('present').onclick=()=>{ if(!$('sv').hidden) return openDeck(sel); const sl=slides.findIndex(s=>s.dataset.notes===pages[cur].id); openDeck(sl<0?0:sl) };
  $('speaker').onclick=openSpeaker;

  // ------------------------------------------------------------ speaker view (second window)
  const notesList=pages.filter(p=>/^(Speaker notes|Q&A)/.test(p.querySelector('.crumb').textContent.trim())&&p.id!=='about-the-notes');
  let st={i:0,step:0,el:0,run:false,black:false}, lastSeen=0, ni=-1, shownFor=-1;
  function mini(el,i,step,label){
    el.innerHTML='';
    if(i>=slides.length){el.innerHTML='<div class="term-off">End of the deck</div>';return}
    const sg=document.createElement('div'); sg.className='stage';
    const c=slides[i].cloneNode(true); c.classList.add('on'); c.querySelectorAll('.f').forEach((f,j)=>f.classList.toggle('on',j<step));
    sg.appendChild(c); el.appendChild(sg); fitMini(el);
  }
  function fitMini(el){const sg=el.querySelector('.stage'); if(sg) sg.style.setProperty('--k',el.clientWidth/1920)}
  function fitMinis(){document.querySelectorAll('.mini').forEach(fitMini)}
  function setNotes(k){
    ni=(k+notesList.length)%notesList.length; const p=notesList[ni];
    $('snotes').innerHTML='<div class="nh"><button id="nprev">◀</button><span>'+esc(p.querySelector('.crumb').textContent.trim())+'</span><button id="nnext">▶</button></div>'+p.innerHTML;
    $('nprev').onclick=()=>setNotes(ni-1); $('nnext').onclick=()=>setNotes(ni+1);
    $('snotes').scrollTop=0;
    const pl=planOf(p.id); $('splan').textContent=pl?'planned '+pl:'';
  }
  function renderSpk(){
    const s=slides[st.i]; if(!s) return;
    mini($('mcur'),st.i,st.step);
    const nx=st.step<steps(s)?[st.i,st.step+1]:[st.i+1,0]; mini($('mnext'),nx[0],nx[1]);
    $('snum').textContent=(st.i+1)+' / '+slides.length+(steps(s)?'  ·  step '+st.step+'/'+steps(s):'');
    document.querySelectorAll('#sstrip .st').forEach((d,j)=>{ d.classList.toggle('on',j===st.i); const m=d.querySelector('.mini'); if(!m.firstChild) mini(m,j,steps(slides[j])); else fitMini(m) });
    if(shownFor!==st.i){ shownFor=st.i; const k=notesList.findIndex(p=>p.id===s.dataset.notes); setNotes(k<0?0:k) }
  }
  function tickSpk(){
    const el=st.el+(st.run&&lastSeen?Date.now()-lastSeen:0); $('sclk').textContent=fmt(el);
    const nxt=notesList[ni+1], pl=nxt?planOf(nxt.id):''; $('sclk').classList.toggle('late', pl? el>secs(pl) : el>40*60000);
    const ok=Date.now()-lastSeen<3000; $('slink').textContent=ok?(st.open?'● connected — presenting':'● connected — deck closed'):'○ not connected — open the deck with ▶ Present';
    $('slink').classList.toggle('ok',ok);
    $('sblack').textContent=st.black?'Unblank':'Black';
    document.querySelectorAll('#spk [data-layout]').forEach(b=>b.classList.toggle('on',b.dataset.layout===st.layout));
  }
  function onSpk(m,trusted){ if(!trusted||!m||m.t!=='state') return; st=m; lastSeen=Date.now(); renderSpk(); tickSpk() }
  function cmd(m){
    const live=Date.now()-lastSeen<3000;
    if(live){ try{window.opener&&window.opener.postMessage(m,'*')}catch(e){} if(!window.opener&&bc) bc.postMessage(m) }
    else if(m.t==='to'){ st.i=m.i; st.step=0; renderSpk() }
    else if(m.t==='go'){ const s=slides[st.i]; if(m.d>0){ if(st.step<steps(s)) st.step++; else if(st.i<slides.length-1){st.i++;st.step=0} } else { if(st.step>0) st.step--; else if(st.i>0){st.i--;st.step=steps(slides[st.i])} } renderSpk() }
  }
  function startSpeaker(){
    document.title='Presenter view - RHACS Threat Detection and Response';
    $('spk').hidden=false; body.classList.add('presenting');
    $('sprev').onclick=()=>cmd({t:'go',d:-1}); $('snext').onclick=()=>cmd({t:'go',d:1});
    $('stimer').onclick=()=>cmd({t:'timer'});
    $('sfontm').onclick=()=>cmd({t:'font',d:-2}); $('sfontp').onclick=()=>cmd({t:'font',d:2});
    $('srestart').onclick=()=>{ if(confirm('Restart all five terminals from zero?')) cmd({t:'restart-all'}) }; $('sreset').onclick=()=>cmd({t:'reset'}); $('sblack').onclick=()=>cmd({t:'black'});
    $('mnext').onclick=()=>cmd({t:'go',d:1}); $('mcur').onclick=()=>cmd({t:'go',d:1});
    const strip=$('sstrip');
    slides.forEach((sl,j)=>{ const d=document.createElement('div'); d.className='st'; d.innerHTML='<b>'+(j+1)+'</b><div class="mini"></div>'; d.onclick=()=>cmd({t:'to',i:j,step:0}); strip.appendChild(d) });
    // a clicked button must not keep the focus: Space/Enter would "click" it again and skip a step
    document.querySelectorAll('#spk button').forEach(b=>b.addEventListener('click',()=>b.blur()));
    renderSpk(); tickSpk(); setInterval(tickSpk,500);
    try{window.opener&&window.opener.postMessage({t:'hello'},'*')}catch(e){} try{bc&&bc.postMessage({t:'hello'})}catch(e){}
  }

  // ------------------------------------------------------------ keyboard
  document.addEventListener('keydown',e=>{
    if(e.target.matches('input,textarea')||e.ctrlKey||e.metaKey||e.altKey) return;
    const k=e.key, nextK=['ArrowRight','PageDown',' ','Enter','ArrowDown'], prevK=['ArrowLeft','PageUp','Backspace','ArrowUp'];
    if(SPEAKER){
      if(e.target.closest && e.target.closest('button')) e.target.blur();
      if(nextK.includes(k)){e.preventDefault();cmd({t:'go',d:1})}
      else if(prevK.includes(k)){e.preventDefault();cmd({t:'go',d:-1})}
      else if(k==='t') cmd({t:'timer'}); else if(k==='r') cmd({t:'reset'}); else if(k==='b'||k==='.') cmd({t:'black'});
      else if(k===']') setNotes(ni+1); else if(k==='[') setNotes(ni-1);
      else if(/^[1-4]$/.test(k)) cmd({t:'layout',name:['all','attack','shell','respond'][+k-1]});
      return;
    }
    if(!deck.hidden){
      if(nextK.includes(k)){e.preventDefault();go(1)}
      else if(prevK.includes(k)){e.preventDefault();go(-1)}
      else if(k==='Home'){e.preventDefault();to(0,0)} else if(k==='End'){e.preventDefault();to(slides.length-1,0)}
      else if(k==='Escape') closeDeck(); else if(k==='s') openSpeaker(); else if(k==='t') toggleTimer();
      else if(k==='b'||k==='.') toggleBlack(); else if(k==='f') toggleFS();
      else if(/^[1-4]$/.test(k) && !$('terms').hidden) layout(['all','attack','shell','respond'][+k-1]);
      else if(k==='r' && !$('terms').hidden){ termsMounted=false; mountTerms() }
      else if(k==='R' && !$('terms').hidden) restartAll();
      else if((k==='+'||k==='=') && !$('terms').hidden) fontAll(2);
      else if(k==='-' && !$('terms').hidden) fontAll(-2);
      return;
    }
    if(k==='Escape'){zoom.style.display='none';body.classList.remove('nav-open');ssm.hidden=true;return}
    if(!$('sv').hidden){
      if(['ArrowDown','ArrowRight','PageDown'].includes(k)){e.preventDefault();select(sel+1)}
      else if(['ArrowUp','ArrowLeft','PageUp'].includes(k)){e.preventDefault();select(sel-1)}
      else if(k==='Home'){e.preventDefault();select(0)} else if(k==='End'){e.preventDefault();select(slides.length-1)}
      else if(k==='Enter'||k==='p') openDeck(sel); else if(k==='s') openSpeaker();
      return;
    }
    if(k==='ArrowRight'||k==='PageDown'){e.preventDefault();show(cur+1)}
    else if(k==='ArrowLeft'||k==='PageUp'){e.preventDefault();show(cur-1)}
    else if(k==='p') $('present').click(); else if(k==='s') openSpeaker();
    else if(k==='/'){e.preventDefault();q.focus()}
  });

  // ------------------------------------------------------------ slides view (like Google Slides)
  const film=$('film'); let sel=0;
  slides.forEach((s,j)=>{ const d=document.createElement('div'); d.className='fi'; d.innerHTML='<span class="no">'+(j+1)+'</span><div class="mini"></div>';
    d.onclick=()=>select(j); d.ondblclick=()=>openDeck(j); film.appendChild(d) });
  const fis=[...film.querySelectorAll('.fi')];
  function fitBig(){ const c=$('canvas'), b=$('bigslide'); if(!c.clientWidth) return; const w=Math.min(c.clientWidth-56, (c.clientHeight-44)*16/9); b.style.width=Math.max(200,w)+'px'; fitMini(b) }
  function select(j,noHash){
    sel=Math.max(0,Math.min(slides.length-1,j)); fis.forEach((f,k)=>f.classList.toggle('sel',k===sel));
    fis[sel].scrollIntoView({block:'nearest'});
    mini($('bigslide'),sel,steps(slides[sel])); fitBig();
    const np=pages[byId(slides[sel].dataset.notes)];
    $('svbody').innerHTML=np?np.innerHTML:''; $('svname').textContent=np?np.querySelector('h2').textContent:'';
    const pl=np?planOf(np.id):''; $('svplan').textContent=pl?'⏱ '+pl:'';
    S.set('talk-sel',sel); if(!noHash) history.replaceState(null,'','#slide-'+(sel+1));
  }
  function view(v){
    const sv=v==='slides'; body.classList.toggle('sv-on',sv); $('sv').hidden=!sv;
    $('tab-slides').setAttribute('aria-selected',sv); $('tab-guide').setAttribute('aria-selected',!sv);
    S.set('talk-view',v);
    if(sv){ fis.forEach((f,k)=>mini(f.querySelector('.mini'),k,steps(slides[k]))); select(sel) } else show(cur);
  }
  $('tab-slides').onclick=()=>view('slides'); $('tab-guide').onclick=()=>view('guide');
  addEventListener('resize',()=>{ if(!$('sv').hidden){ fitBig(); fis.forEach(f=>fitMini(f.querySelector('.mini'))) } });
  // Slideshow menu
  const ssm=$('ssm');
  $('ssmenu').onclick=e=>{e.stopPropagation(); ssm.hidden=!ssm.hidden};
  document.addEventListener('click',()=>ssm.hidden=true);
  ssm.querySelectorAll('[data-ss]').forEach(b=>b.onclick=()=>{ ssm.hidden=true; const a=b.dataset.ss;
    if(a==='start') openDeck(0); else if(a==='current') $('present').click(); else openSpeaker() });
  // notes font size in presenter view
  let nf=parseInt(S.get('talk-nf')||'23',10);
  const setNf=v=>{nf=Math.max(14,Math.min(44,v)); $('snotes').style.setProperty('--nf',nf+'px'); S.set('talk-nf',nf)};
  setNf(nf); $('sfm').onclick=()=>setNf(nf-2); $('sfp').onclick=()=>setNf(nf+2);

  // ------------------------------------------------------------ start
  let i=byId(location.hash.slice(1)); if(i<0) i=byId(S.get('talk-page')||''); cur=i<0?0:i;
  const hs=/^#slide-(\d+)$/.exec(location.hash); sel=hs?(+hs[1]-1):(parseInt(S.get('talk-sel')||'0',10)||0);
  view(byId(location.hash.slice(1))>=0 ? 'guide' : (hs ? 'slides' : (S.get('talk-view')||'slides')));
  if(SPEAKER) startSpeaker();
  else if(Q.has('present')){ const n=parseInt(Q.get('present'),10); openDeck(isNaN(n)?0:n-1); if(Q.has('step')) to(di,parseInt(Q.get('step'),10)||0); if(Q.has('layout')) layout(Q.get('layout')) }
})();
'''

page = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RHACS Threat Detection and Response</title>
{FONTS}
<style>{CSS}</style></head>
<body>
<header>
  <button id="menu" aria-label="Menu">☰</button>
  <div class="brand"><i></i>RHACS - Threat Detection and Response</div>
  <nav class="tabs" role="tablist"><button id="tab-slides" role="tab">Slides</button><button id="tab-guide" role="tab">Guide</button></nav>
  <span class="sp"></span>
  <div class="ssbtn"><button id="present" class="primary" title="Present from the current slide (p)">▶ Slideshow</button><button id="ssmenu" class="primary caret" aria-label="More slideshow options" aria-haspopup="menu">▾</button>
    <div class="menu" id="ssm" hidden role="menu"><button data-ss="current" role="menuitem">Present from current slide</button><button data-ss="start" role="menuitem">Present from beginning</button><button data-ss="presenter" role="menuitem">Presenter view <small>notes, timer, next slide</small></button></div></div>
  <button id="speaker" hidden></button>
  <button id="theme" title="Light / dark" aria-label="Toggle theme">◐</button>
</header>
<div id="sv" hidden>
  <div class="film" id="film" aria-label="Slides"></div>
  <div class="canvas" id="canvas"><div class="mini big" id="bigslide"></div></div>
  <div class="svnotes"><div class="svh"><span>Speaker notes</span><span class="svplan" id="svplan"></span><span class="sp"></span><span class="svname" id="svname"></span></div><div id="svbody"></div></div>
</div>
<aside><input id="q" class="search" type="search" placeholder="Search…  ( / )">{nav}</aside>
<main>
{secs}
<div class="pager"><button id="prev"></button><button id="next" class="next"></button></div>
<div class="hint">← → move · p slideshow · s presenter view · / search</div>
</main>
<div id="zoom"><img alt=""></div>

<div id="deck" hidden role="dialog" aria-label="Slides">
  <div class="stage" id="stage">
{deck_html}  </div>
  <div id="terms" hidden>
    <div class="tgrid" id="ws">{terms_html}<div id="drop" hidden></div></div>
    <div class="tdock" id="dock"><span class="dl">Minimized - click to restore:</span></div>
  </div>
  <div id="black" hidden></div>
</div>

<div id="spk" hidden>
  <div class="sbar"><span class="ttl">Presenter view</span><span class="clk" id="sclk">0:00</span><span class="plan" id="splan"></span>
    <button id="stimer" title="Start / pause (t)">⏱ Start / pause</button><button id="sreset" title="Reset timer (r)">↺</button>
    <span class="sp"></span><span class="link" id="slink"></span><span class="num" id="snum"></span>
    <button id="sfm" title="Smaller notes">A−</button><button id="sfp" title="Bigger notes">A+</button><button id="sblack" title="Black screen (b)">Black</button><button id="sprev" title="Previous (←)">← Prev</button><button id="snext" title="Next (→)">Next →</button></div>
  <div class="snotes" id="snotes"></div>
  <div class="sside"><div><div class="lbl">On screen now</div><div class="mini" id="mcur"></div></div>
    <div><div class="lbl">Next — click to advance</div><div class="mini next" id="mnext" title="Click to advance"></div></div>
    <div><div class="lbl">All slides — click to jump</div><div class="sstrip" id="sstrip"></div></div>
    <div><div class="lbl">Terminal layout</div><div class="slays">{layout_btns}<button id="sfontm" title="Smaller terminal text">Text A−</button><button id="sfontp" title="Bigger terminal text">Text A+</button><button id="srestart" title="Restart all five terminals from zero">↻ Restart all</button></div></div>
    <div class="skeys">In the slideshow there are no buttons: keyboard only. It fills the browser tab (tabs stay visible); f toggles true full screen. Esc exits.<br>→ / Space next · ← back · t timer · r reset · b black screen · [ ] other notes · 1–4 terminal layout · + / − terminal text<br>During the live demo, keep this window focused to change slides while the terminals stay on screen.</div></div>
</div>
<script>{JS}</script>
</body></html>'''
(D / "TALK.html").write_text(page, encoding="utf-8")
print("pages:", len(pages), "· slides:", len(SLIDES))
