// Unhackable Blog — RHACS Threat Detection & Response demo application.
//
// The image ships with ZERO CVEs and a minimal RHACS risk score. The flaw is
// not in a dependency: it is a shortcut in our own code (see linkcheck_v1.go).
// No scanner can find it — only runtime detection can catch it being abused.
//
// Modes:
//
//	blog      (default) the public blog + post editor with "Check links"
//	payments  a tiny internal payments API — the attacker's lateral-movement target
package main

import (
	"bytes"
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

// version is set at build time: -ldflags "-X main.version=v1"
var version = "dev"

//go:embed web/*
var webFS embed.FS

type Post struct {
	Slug, Title, Author, Date, Summary string
	Body                               []string
}

var posts = []Post{
	{
		Slug: "zero-cves", Title: "We shipped with zero CVEs. Here's how.", Author: "Platform Team", Date: "2026-11-02",
		Summary: "Static Go binary, minimal Alpine base, patched on every build. Our scanner report is a single green line.",
		Body: []string{
			"Every image we ship is rebuilt nightly on the latest Alpine release with every package upgraded.",
			"The application is a single static Go binary with no third-party dependencies. Nothing to patch means nothing to exploit.",
			"Our vulnerability scanner reports exactly zero CVEs. Not low, not moderate. Zero.",
		},
	},
	{
		Slug: "hardened-by-default", Title: "Hardened by default: no root, no token, no write", Author: "Security Champions", Date: "2026-11-05",
		Summary: "Read-only root filesystem, every capability dropped, no service account token. Good luck, attackers.",
		Body: []string{
			"Our pods run as a random non-root UID with every Linux capability dropped and privilege escalation disabled.",
			"The root filesystem is read-only. There is no Kubernetes service account token mounted. The package manager is gone, so nothing new can be installed at runtime.",
			"Our deployment passes every admission policy we have. The risk score is the lowest in the cluster.",
		},
	},
	{
		Slug: "link-checker", Title: "New: never publish a broken link again", Author: "Dev Team", Date: "2026-11-09",
		Summary: "Writers asked, we delivered. The editor now checks every link in your draft before you publish.",
		Body: []string{
			"Paste your draft into the editor and press Check links. We verify every URL is alive before it goes live.",
			"We shipped it in an afternoon. Power users can even attach a little Go rule to validate links — we run them safely in an embedded sandbox. The scanner is still green: zero CVEs.",
		},
	},
}

var tmpl = template.Must(template.New("").Funcs(template.FuncMap{
	"dict": func(kv ...any) map[string]any {
		m := map[string]any{}
		for i := 0; i+1 < len(kv); i += 2 {
			m[kv[i].(string)] = kv[i+1]
		}
		return m
	},
}).ParseFS(webFS, "web/*.html"))

func render(w http.ResponseWriter, name string, data any) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := tmpl.ExecuteTemplate(w, name, data); err != nil {
		log.Printf("template %s: %v", name, err)
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

// ---------------------------------------------------------------- access log
// Every request is logged in the classic HTTP access-log format, so the app's own
// log reads like any web server: method, path, status, size, client. During the demo
// every attack arrives here as an ordinary-looking POST /api/links/check — the app sees
// nothing wrong, which is exactly why runtime detection (RHACS) earns its place.

var accessLog = log.New(os.Stdout, "", 0) // no std prefix: the line carries its own timestamp

type statusWriter struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (s *statusWriter) WriteHeader(code int) { s.status = code; s.ResponseWriter.WriteHeader(code) }
func (s *statusWriter) Write(b []byte) (int, error) {
	if s.status == 0 {
		s.status = http.StatusOK
	}
	n, err := s.ResponseWriter.Write(b)
	s.bytes += n
	return n, err
}

// clientIP prefers X-Forwarded-For (set by the OpenShift route) so the log shows the
// real caller, not the in-cluster router address.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if i := strings.IndexByte(xff, ','); i >= 0 {
			return strings.TrimSpace(xff[:i])
		}
		return strings.TrimSpace(xff)
	}
	host := r.RemoteAddr
	if i := strings.LastIndexByte(host, ':'); i >= 0 {
		host = host[:i]
	}
	return host
}

// checkedURLs pulls the url(s) the caller submitted — query string, form body, or JSON — so
// the access log shows exactly what was "checked". For an attack that's the injected command
// sitting in plain sight (url=';cat /opt/blog/.env #').
func checkedURLs(r *http.Request, body []byte) string {
	var urls []string
	urls = append(urls, r.URL.Query()["url"]...)
	if strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		var req struct {
			URLs []string `json:"urls"`
		}
		if json.Unmarshal(body, &req) == nil {
			urls = append(urls, req.URLs...)
		}
	} else if vals, err := url.ParseQuery(string(body)); err == nil {
		urls = append(urls, vals["url"]...)
	}
	s := strings.TrimSpace(strings.Join(urls, " "))
	if len(s) > 256 {
		s = s[:256] + "…"
	}
	return s
}

func withAccessLog(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Skip the kube-probe health checks — they fire every few seconds and are pure noise.
		if r.URL.Path == "/healthz" {
			h.ServeHTTP(w, r)
			return
		}
		// Buffer the body so we can log the submitted params AND still let the handler read it.
		var body []byte
		if r.Body != nil && r.ContentLength != 0 {
			body, _ = io.ReadAll(io.LimitReader(r.Body, 64<<10))
			r.Body = io.NopCloser(bytes.NewReader(body))
		}
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		h.ServeHTTP(sw, r)
		ua := r.UserAgent()
		if ua == "" {
			ua = "-"
		}
		line := fmt.Sprintf("%s - - [%s] \"%s %s %s\" %d %d %q",
			clientIP(r), start.Format("02/Jan/2006:15:04:05 -0700"),
			r.Method, r.RequestURI, r.Proto, sw.status, sw.bytes, ua)
		if u := checkedURLs(r, body); u != "" {
			line += fmt.Sprintf(" url=%q", u)
		}
		accessLog.Print(line)
	})
}

// ---------------------------------------------------------------- link checker

type LinkResult struct {
	URL    string `json:"url"`
	Status string `json:"status"`
	Detail string `json:"detail,omitempty"`
}

// cacheFile persists the last check results in the app's own cache volume.
// The app never writes anywhere else — so anything new in /tmp is not ours.
const cacheFile = "/var/cache/blog/linkcheck.json"

var cacheMu sync.Mutex

func handleCheckLinks(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST only"})
		return
	}
	var req struct {
		URLs []string `json:"urls"`
	}
	// Two ways in: JSON from the editor page, or a plain form post
	// (curl --data-urlencode "url=..."), which gets a plain-text answer.
	form := !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json")
	if form {
		r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
		if err := r.ParseForm(); err != nil {
			http.Error(w, "invalid form", http.StatusBadRequest)
			return
		}
		req.URLs = r.PostForm["url"]
	} else if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if len(req.URLs) > 20 {
		req.URLs = req.URLs[:20]
	}
	results := make([]LinkResult, 0, len(req.URLs))
	for _, u := range req.URLs {
		u = strings.TrimSpace(u)
		if u == "" {
			continue
		}
		results = append(results, checkLink(u)) // linkcheck_v1.go or linkcheck_v2.go
	}
	cacheMu.Lock()
	if b, err := json.Marshal(results); err == nil {
		_ = os.WriteFile(cacheFile, b, 0o600)
	}
	cacheMu.Unlock()
	if form {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		for _, res := range results {
			if res.Detail != "" {
				fmt.Fprintln(w, res.Detail)
			} else {
				fmt.Fprintf(w, "%s: %s\n", res.Status, res.URL)
			}
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"results": results, "checker": checkerName})
}

// ---------------------------------------------------------------- payments mode

func paymentsMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	mux.HandleFunc("/api/v1/status", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, 200, map[string]string{"service": "payments-api", "version": version, "status": "processing"})
	})
	mux.HandleFunc("/api/v1/cards", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("CARD DATA requested by %s", r.RemoteAddr)
		writeJSON(w, 200, map[string]any{
			"warning": "internal use only — PCI scope",
			"cards": []map[string]string{
				{"holder": "A. Lovelace", "pan": "4111 1111 1111 1111", "exp": "08/29"},
				{"holder": "G. Hopper", "pan": "5500 0000 0000 0004", "exp": "11/28"},
				{"holder": "K. Johnson", "pan": "3400 0000 0000 009", "exp": "02/30"},
			},
		})
	})
	return mux
}

// ---------------------------------------------------------------- blog mode

func blogMux() *http.ServeMux {
	mux := http.NewServeMux()
	page := func(extra map[string]any) map[string]any {
		d := map[string]any{"Version": version, "Checker": checkerName, "Posts": posts, "Year": time.Now().Year()}
		for k, v := range extra {
			d[k] = v
		}
		return d
	}
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	mux.HandleFunc("/api/links/check", handleCheckLinks)
	mux.HandleFunc("/write", func(w http.ResponseWriter, _ *http.Request) { render(w, "write.html", page(nil)) })
	mux.HandleFunc("/post/", func(w http.ResponseWriter, r *http.Request) {
		slug := strings.TrimPrefix(r.URL.Path, "/post/")
		for _, p := range posts {
			if p.Slug == slug {
				render(w, "post.html", page(map[string]any{"Post": p}))
				return
			}
		}
		http.NotFound(w, r)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		render(w, "index.html", page(nil))
	})
	return mux
}

func main() {
	mode := flag.String("mode", envOr("MODE", "blog"), "blog | payments")
	addr := flag.String("listen", envOr("LISTEN", ":8080"), "listen address")
	flag.Parse()

	var h http.Handler
	switch *mode {
	case "blog":
		h = blogMux()
	case "payments":
		h = paymentsMux()
	default:
		log.Fatalf("unknown mode %q", *mode)
	}
	srv := &http.Server{Addr: *addr, Handler: withAccessLog(h), ReadHeaderTimeout: 5 * time.Second}
	log.Printf("unhackable %s %s (checker=%s) listening on %s", *mode, version, checkerName, *addr)
	log.Fatal(srv.ListenAndServe())
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
