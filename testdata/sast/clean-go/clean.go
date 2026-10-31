// SPDX-License-Identifier: MIT

// Package clean does safely what the vulnerable fixture does unsafely, and
// neither scanner has anything to report on it.
package clean

import (
	"context"
	"crypto/subtle"
	"crypto/tls"
	"encoding/binary"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
)

const maxFrame = 4096

// Config verifies certificates.
func Config() *tls.Config {
	return &tls.Config{MinVersion: tls.VersionTLS13}
}

// Frame checks the length from the wire before allocating.
func Frame(b []byte) ([]byte, error) {
	n := binary.BigEndian.Uint16(b)
	if n > maxFrame || int(n) > len(b)-2 {
		return nil, errors.New("frame too long")
	}
	out := make([]byte, 0, n)
	return append(out, b[2:2+int(n)]...), nil
}

// Link runs a fixed command with no shell.
func Link(ctx context.Context) error {
	return exec.CommandContext(ctx, "ip", "link", "show").Run()
}

// Index reads a fixed path.
func Index() ([]byte, error) {
	return os.ReadFile(filepath.Join("testdata", "index.html"))
}

// Same compares in constant time.
func Same(a, b []byte) bool {
	return subtle.ConstantTimeCompare(a, b) == 1
}
