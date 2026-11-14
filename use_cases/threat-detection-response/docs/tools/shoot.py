"""Screenshot helper for the walkthrough (runs inside the Playwright container).

usage:  python shoot.py SHOTS.json OUTDIR

SHOTS.json: list of shots, each one of
  {"name": "act1-vuln", "url": "https://...", "rhacs": true,
   "wait": "text or css to wait for", "click": ["text=..."], "fill": [["css","value"]],
   "full": false, "delay": 2000, "highlight": "text to outline"}
  {"name": "act2-term", "terminal": "path/to/ansi.txt", "title": "demo.sh act2"}

env: ROX_PASSWORD (RHACS admin password; never printed)
"""
import html
import json
import os
import re
import sys

from playwright.sync_api import sync_playwright

VIEW = {"width": 1600, "height": 1000}

ANSI_COLORS = {
    "30": "#1e1e1e", "31": "#ff6b6b", "32": "#69db7c", "33": "#ffd43b", "34": "#74c0fc",
    "35": "#e599f7", "36": "#66d9e8", "37": "#e9ecef", "90": "#868e96",
}


def ansi_to_html(text: str) -> str:
    out, style = [], {"bold": False, "dim": False, "color": None}
    pos = 0

    def span(chunk):
        if not chunk:
            return
        css = []
        if style["color"]:
            css.append(f"color:{style['color']}")
        if style["bold"]:
            css.append("font-weight:700")
        if style["dim"]:
            css.append("opacity:.6")
        esc = html.escape(chunk)
        out.append(f'<span style="{";".join(css)}">{esc}</span>' if css else esc)

    for m in re.finditer(r"\x1b\[([0-9;]*)m", text):
        span(text[pos:m.start()])
        pos = m.end()
        for code in (m.group(1) or "0").split(";"):
            if code in ("0", ""):
                style = {"bold": False, "dim": False, "color": None}
            elif code == "1":
                style["bold"] = True
            elif code == "2":
                style["dim"] = True
            elif code in ANSI_COLORS:
                style["color"] = ANSI_COLORS[code]
    span(text[pos:])
    return "".join(out)


TERM_PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
body{margin:0;background:#0b1220;padding:28px;font-family:system-ui,sans-serif}
.win{border-radius:12px;overflow:hidden;box-shadow:0 20px 60px rgba(0,0,0,.5);max-width:1500px;margin:0 auto}
.bar{background:#2b3245;color:#cbd5e1;font-size:14px;padding:10px 16px;display:flex;align-items:center;gap:8px}
.dot{width:12px;height:12px;border-radius:50%;display:inline-block}
pre{margin:0;background:#11161f;color:#e9ecef;padding:22px 26px;font:15px/1.55 "JetBrains Mono","DejaVu Sans Mono",monospace;white-space:pre-wrap;word-break:break-all}
</style></head><body><div class="win"><div class="bar"><span class="dot" style="background:#ff5f57"></span>
<span class="dot" style="background:#febc2e"></span><span class="dot" style="background:#28c840"></span>
<span style="margin-left:10px">__TITLE__</span></div><pre>__BODY__</pre></div></body></html>"""


def rhacs_login(page, base):
    page.goto(base + "/login", wait_until="domcontentloaded")
    page.wait_for_timeout(2500)
    if "/login" not in page.url:
        return
    # basic auth provider form
    page.locator("input[name='username'], input#username").first.fill("admin")
    page.locator("input[name='password'], input#password, input[type='password']").first.fill(os.environ["ROX_PASSWORD"])
    page.locator("button[type='submit'], button:has-text('Log in')").first.click()
    page.wait_for_url(re.compile(r".*/main/.*"), timeout=60000)


def main():
    shots = json.load(open(sys.argv[1]))
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--ignore-certificate-errors", "--allow-file-access-from-files"])
        ctx = browser.new_context(viewport=VIEW, ignore_https_errors=True, device_scale_factor=1)
        page = ctx.new_page()
        logged_in = set()
        for s in shots:
            path = os.path.join(outdir, s["name"] + ".png")
            try:
                if "terminal" in s:
                    body = ansi_to_html(open(s["terminal"], encoding="utf-8", errors="replace").read().rstrip())
                    page.set_content(TERM_PAGE.replace("__TITLE__", html.escape(s.get("title", "terminal"))).replace("__BODY__", body))
                    page.locator(".win").screenshot(path=path)
                    print("ok", s["name"])
                    continue
                if s.get("rhacs"):
                    base = re.match(r"https://[^/]+", s["url"]).group(0)
                    if base not in logged_in:
                        rhacs_login(page, base)
                        logged_in.add(base)
                page.set_viewport_size(s.get("size", VIEW))
                page.goto(s["url"], wait_until="domcontentloaded", timeout=60000)
                if s.get("wait"):
                    try:
                        page.get_by_text(s["wait"]).first.wait_for(timeout=30000)
                    except Exception:
                        page.locator(s["wait"]).first.wait_for(timeout=15000)
                for sel, val in s.get("fill", []):
                    page.locator(sel).first.fill(val)
                for sel in s.get("click", []):
                    force = sel.startswith("force:")
                    sel = sel.removeprefix("force:")
                    if sel.startswith("exact:"):
                        page.get_by_text(sel.removeprefix("exact:"), exact=True).first.click(force=force)
                    else:
                        page.locator(sel).first.click(force=force)
                    page.wait_for_timeout(2500)
                page.wait_for_timeout(s.get("delay", 2500))
                if s.get("highlight"):
                    try:
                        page.get_by_text(s["highlight"]).first.evaluate(
                            "e => { e.style.outline='4px solid #e8590c'; e.style.outlineOffset='3px'; e.style.borderRadius='4px'; }")
                    except Exception:
                        pass
                page.screenshot(path=path, full_page=s.get("full", False))
                print("ok", s["name"])
            except Exception as e:  # keep going; report
                page.screenshot(path=path)
                print("WARN", s["name"], type(e).__name__, str(e)[:160])
        browser.close()


if __name__ == "__main__":
    main()
