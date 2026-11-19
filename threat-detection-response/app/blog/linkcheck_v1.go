//go:build !fixed

package main

import (
	"fmt"
	"net/http"
	"net/url"
	"os/exec"
	"reflect"
	"strings"
	"time"

	"github.com/traefik/yaegi/interp"
	"github.com/traefik/yaegi/stdlib"
)

const checkerName = "rules"

var ruleClient = &http.Client{Timeout: 3 * time.Second}

// checkLink — v1, the "smart link rules" engine.
//
// Writers asked for more than a yes/no link check, so the editor lets them attach a short Go
// "rule" to validate a link. The app runs the rule through an embedded Go interpreter (yaegi).
// yaegi is careful — by default it keeps os/exec out of the sandbox — but we wanted rules to
// run a quick helper, so we handed the engine exec.Command (see below).
//
// THE BUG (CWE-94, code injection): a "rule" is untrusted input evaluated as code, and we gave
// that code exec.Command — so it runs host commands. The application itself never shells out;
// the interpreter does, on the attacker's behalf. yaegi is a clean dependency — the scanner
// reports 0 CVEs — because the flaw is not IN yaegi, it is handing it a dangerous capability
// and feeding it untrusted input. No scanner can see that. Fixed in linkcheck_v2.go.
//
// A plain URL is checked natively (no interpreter), so normal use spawns NO child process at
// all, and the RHACS process baseline for this container is a single binary: /usr/local/bin/blog.
func checkLink(input string) LinkResult {
	input = strings.TrimSpace(input)

	// A real http(s) URL? Validate it natively — the interpreter is never involved.
	if u, err := url.Parse(input); err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != "" {
		resp, err := ruleClient.Head(input)
		if err != nil {
			return LinkResult{URL: input, Status: "dead", Detail: ""}
		}
		resp.Body.Close()
		status := "alive"
		if resp.StatusCode >= 400 {
			status = "dead"
		}
		return LinkResult{URL: input, Status: status, Detail: ""}
	}

	// Otherwise treat it as an advanced rule and evaluate it as Go.
	i := interp.New(interp.Options{})
	if err := i.Use(stdlib.Symbols); err != nil {
		return LinkResult{URL: input, Status: "error", Detail: "rule engine unavailable"}
	}
	// yaegi deliberately keeps os/exec out of its sandbox — but we wanted rules to be able to
	// run a quick validation helper, so we handed it exec.Command. That one line is the whole
	// breach: a sandbox with os/exec in it is not a sandbox.
	i.Use(interp.Exports{"os/exec/exec": map[string]reflect.Value{
		"Command": reflect.ValueOf(exec.Command),
	}})
	// Preload the packages a rule might use.
	if _, err := i.Eval(`import ("os/exec"; "net/http"; "encoding/base64"; "time")`); err != nil {
		return LinkResult{URL: input, Status: "error", Detail: "rule imports failed"}
	}
	v, err := i.Eval(input)
	if err != nil {
		return LinkResult{URL: input, Status: "rejected", Detail: firstLine(err.Error())}
	}
	return LinkResult{URL: input, Status: "checked", Detail: ruleValue(v)}
}

func ruleValue(v reflect.Value) string {
	if !v.IsValid() {
		return ""
	}
	if v.Kind() == reflect.String {
		return strings.TrimRight(v.String(), "\n")
	}
	return strings.TrimRight(fmt.Sprintf("%v", v.Interface()), "\n")
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}
