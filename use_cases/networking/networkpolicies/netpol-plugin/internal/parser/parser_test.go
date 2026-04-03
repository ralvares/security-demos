package parser_test

import (
	"testing"

	"github.com/ralvares/kubectl-netpol/internal/parser"
)

func TestParse(t *testing.T) {
	tests := []struct {
		input     string
		wantNS    string
		wantWL    string
		wantPort  string
		wantProto string
		wantTUI   bool
		wantErr   bool
	}{
		{"ns/app/+", "ns", "app", "+", "", false, false},
		{"ns/app/80/tcp", "ns", "app", "80", "TCP", false, false},
		{"ns/app", "ns", "app", "", "", true, false},
		{"ns/+", "ns", "+", "", "", false, false},
		{"+", "+", "+", "", "", false, false},
		{"ns/app/80", "ns", "app", "80", "", false, false},
		{"", "", "", "", "", false, true},
		{"ns/app/80/badproto", "", "", "", "", false, true},
	}
	for _, tc := range tests {
		t.Run(tc.input, func(t *testing.T) {
			ref, err := parser.Parse(tc.input)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if ref.Namespace != tc.wantNS {
				t.Errorf("namespace: got %q want %q", ref.Namespace, tc.wantNS)
			}
			if ref.Workload != tc.wantWL {
				t.Errorf("workload: got %q want %q", ref.Workload, tc.wantWL)
			}
			if ref.Port != tc.wantPort {
				t.Errorf("port: got %q want %q", ref.Port, tc.wantPort)
			}
			if ref.Protocol != tc.wantProto {
				t.Errorf("protocol: got %q want %q", ref.Protocol, tc.wantProto)
			}
			if ref.NeedsTUI() != tc.wantTUI {
				t.Errorf("NeedsTUI: got %v want %v", ref.NeedsTUI(), tc.wantTUI)
			}
		})
	}
}
