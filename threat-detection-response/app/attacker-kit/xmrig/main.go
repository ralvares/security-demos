// xmrig — a HARMLESS crypto-miner look-alike for the RHACS demo.
//
// It is named "xmrig" so RHACS's "Cryptocurrency Mining Process Execution"
// policy recognises it, prints an XMRig-style console, "connects to a pool"
// (the demo mining-pool service) and burns ONE core with SHA-256 for a bounded
// time. It mines nothing, sends nothing of value and exits on its own.
package main

import (
	"bufio"
	"crypto/sha256"
	"flag"
	"fmt"
	"net"
	"os"
	"runtime"
	"strings"
	"time"
)

func main() {
	pool := flag.String("o", "stratum+tcp://127.0.0.1:3333", "pool URL")
	user := flag.String("u", "48edfHu7V9Z84YzzMa6fUueoELZ9ZRXq9VetWzYGzKt52XU5xvqgzYnDK9URnRoJMk1j8nLwEVsaSWJ4fhdUyZijBGUicoD", "wallet")
	dur := flag.Duration("t", 10*time.Minute, "stop after (safety limit)")
	flag.Int("donate-level", 1, "ignored")
	flag.Parse()

	host := strings.TrimPrefix(*pool, "stratum+tcp://")
	fmt.Println(" * ABOUT        XMRig/6.22.2 gcc/13.2.1 (demo simulator — mines nothing)")
	fmt.Printf(" * CPU          %d threads available, using 1\n", runtime.NumCPU())
	fmt.Printf(" * POOL #1      %s algo rx/0\n", host)

	var conn net.Conn
	for i := 0; i < 5 && conn == nil; i++ {
		c, err := net.DialTimeout("tcp", host, 3*time.Second)
		if err == nil {
			conn = c
			break
		}
		fmt.Printf("[%s] net      connect error: %v\n", ts(), err)
		time.Sleep(2 * time.Second)
	}
	if conn != nil {
		defer conn.Close()
		fmt.Fprintf(conn, `{"id":1,"method":"login","params":{"login":"%s","agent":"XMRig/6.22.2"}}`+"\n", *user)
		fmt.Printf("[%s] net      use pool %s\n", ts(), host)
		go func() { // print pool replies
			s := bufio.NewScanner(conn)
			for s.Scan() {
				fmt.Printf("[%s] net      %s\n", ts(), s.Text())
			}
		}()
	}

	deadline := time.Now().Add(*dur)
	var h [32]byte
	n, last := 0, time.Now()
	for time.Now().Before(deadline) {
		h = sha256.Sum256(h[:])
		n++
		if time.Since(last) >= 10*time.Second {
			rate := float64(n) / time.Since(last).Seconds()
			fmt.Printf("[%s] miner    speed 10s %.1f H/s\n", ts(), rate)
			if conn != nil {
				fmt.Fprintf(conn, `{"id":4,"method":"submit","params":{"result":"%x"}}`+"\n", h[:8])
			}
			n, last = 0, time.Now()
		}
	}
	fmt.Println("[simulator] safety limit reached, exiting")
	os.Exit(0)
}

func ts() string { return time.Now().Format("2006-01-02 15:04:05.000") }
