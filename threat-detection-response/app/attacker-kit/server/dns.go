package main

// A tiny authoritative DNS server for the attacker's domain.
//
//	attacker-kit dns     (:5300/udp)  answers A records for *.$ATTACKER_ZONE with $ATTACKER_HOST (an IPv4)
//
// The cluster's DNS forwards the zone here (scripts/attacker.sh up), exactly how
// a real attacker's domain is answered by the attacker's own nameserver.

import (
	"encoding/binary"
	"log"
	"net"
	"os"
	"strings"
)

func dnsServe() {
	zone := strings.ToLower(strings.TrimSuffix(envDefault("ATTACKER_ZONE", "example.local"), "."))
	ip := net.ParseIP(envDefault("ATTACKER_HOST", "127.0.0.1")).To4()
	if ip == nil {
		log.Fatal("ATTACKER_HOST must be an IPv4 address")
	}
	pc, err := net.ListenPacket("udp", ":5300")
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("dns: answering *.%s -> %s on :5300/udp", zone, ip)
	buf := make([]byte, 1500)
	for {
		n, addr, err := pc.ReadFrom(buf)
		if err != nil || n < 12 {
			continue
		}
		if resp, name := dnsAnswer(buf[:n], zone, ip); resp != nil {
			log.Printf("dns: %s asked for %s", addr, name)
			pc.WriteTo(resp, addr)
		}
	}
}

// dnsAnswer builds a response for a single-question query.
func dnsAnswer(q []byte, zone string, ip net.IP) ([]byte, string) {
	if binary.BigEndian.Uint16(q[4:6]) != 1 { // QDCOUNT
		return nil, ""
	}
	// parse QNAME
	var labels []string
	i := 12
	for i < len(q) && q[i] != 0 {
		l := int(q[i])
		if l > 63 || i+1+l > len(q) {
			return nil, ""
		}
		labels = append(labels, string(q[i+1:i+1+l]))
		i += 1 + l
	}
	if i+5 > len(q) {
		return nil, ""
	}
	qEnd := i + 5 // zero byte + QTYPE + QCLASS
	qtype := binary.BigEndian.Uint16(q[i+1 : i+3])
	name := strings.ToLower(strings.Join(labels, "."))

	resp := make([]byte, 0, 512)
	resp = append(resp, q[0:2]...)    // ID
	inZone := name == zone || strings.HasSuffix(name, "."+zone)
	flags := uint16(0x8400)           // QR + AA
	if q[2]&0x01 != 0 {
		flags |= 0x0100 // copy RD
	}
	answers := 0
	if !inZone {
		flags |= 3 // NXDOMAIN
	} else if qtype == 1 || qtype == 255 { // A or ANY
		answers = 1
	}
	resp = binary.BigEndian.AppendUint16(resp, flags)
	resp = binary.BigEndian.AppendUint16(resp, 1)               // QDCOUNT
	resp = binary.BigEndian.AppendUint16(resp, uint16(answers)) // ANCOUNT
	resp = binary.BigEndian.AppendUint16(resp, 0)               // NSCOUNT
	resp = binary.BigEndian.AppendUint16(resp, 0)               // ARCOUNT
	resp = append(resp, q[12:qEnd]...)                          // question
	if answers == 1 {
		resp = append(resp, 0xc0, 0x0c)                     // name pointer to question
		resp = binary.BigEndian.AppendUint16(resp, 1)       // TYPE A
		resp = binary.BigEndian.AppendUint16(resp, 1)       // CLASS IN
		resp = binary.BigEndian.AppendUint32(resp, 30)      // TTL
		resp = binary.BigEndian.AppendUint16(resp, 4)       // RDLENGTH
		resp = append(resp, ip...)
	}
	return resp, name
}

func envDefault(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
