// SPDX-License-Identifier: MIT

// Package vulnerable has one planted weakness per detection the selftest
// expects. It is never built into anything.
package vulnerable

import (
	"crypto/tls"
	"encoding/binary"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
)

// Gosec G101: a hardcoded credential.
const adminPassword = "xK9mQ2vL7pR4nT8wZ3bF6hJ1"

// Reaches outside /srv with "../".
func UnsafePath(r *http.Request) ([]byte, error) {
	return os.ReadFile(filepath.Join("/srv", r.URL.Query().Get("name")))
}

// Gosec G402, high severity and confidence.
func InsecureTLS() *tls.Config {
	return &tls.Config{InsecureSkipVerify: true}
}

// The comment must not waive it: only the baseline does.
func SuppressedTLS() *tls.Config {
	return &tls.Config{InsecureSkipVerify: true} // #nosec G402
}

func WireLength(b []byte) []byte {
	return make([]byte, binary.BigEndian.Uint32(b)) // nosemgrep
}

func Secret(password string) {
	slog.Info("login", "password", password)
}

func Shell(host string) error {
	return exec.Command("sh", "-c", "ping "+host).Run()
}

func Accept(l net.Listener) {
	for {
		c, err := l.Accept()
		if err != nil {
			return
		}
		defer c.Close()
	}
}

func Body(w http.ResponseWriter, r *http.Request) {
	b, _ := io.ReadAll(r.Body)
	_, _ = w.Write(b)
}

func Narrow(n int) int8 {
	return int8(n)
}
