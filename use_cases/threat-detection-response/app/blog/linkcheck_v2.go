//go:build fixed

package main

import (
	"context"
	"net/http"
	"net/url"
	"time"
)

const checkerName = "native"

var client = &http.Client{
	Timeout: 3 * time.Second,
	// never follow redirects into the cluster or anywhere else
	CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
}

// checkLink — v2, the fix.
//
//   - parse and validate the URL instead of pasting it into a shell
//   - only http/https, must have a host
//   - native HTTP client: no shell, no child processes at all
//
// With no child processes, the RHACS process baseline for this container is
// a single entry: /usr/local/bin/blog. Anything else is, by definition, an attack.
func checkLink(raw string) LinkResult {
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return LinkResult{URL: raw, Status: "rejected", Detail: "not a valid http(s) URL"}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	resp, err := fetch(ctx, http.MethodHead, u.String())
	// some servers refuse HEAD — retry with GET (body is discarded)
	if err == nil && (resp.StatusCode == http.StatusMethodNotAllowed || resp.StatusCode == http.StatusForbidden) {
		resp.Body.Close()
		resp, err = fetch(ctx, http.MethodGet, u.String())
	}
	if err != nil {
		return LinkResult{URL: raw, Status: "dead", Detail: "unreachable"}
	}
	resp.Body.Close()
	if resp.StatusCode < 400 {
		return LinkResult{URL: raw, Status: "alive", Detail: resp.Status}
	}
	return LinkResult{URL: raw, Status: "dead", Detail: resp.Status}
}

func fetch(ctx context.Context, method, target string) (*http.Response, error) {
	req, _ := http.NewRequestWithContext(ctx, method, target, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; unhackable-blog-linkcheck/2)")
	return client.Do(req)
}
