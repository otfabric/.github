// SPDX-License-Identifier: MIT

// Package sub is a module of its own.
package sub

import "crypto/tls"

// Insecure is what a scan of the outer module must not see.
func Insecure() *tls.Config {
	return &tls.Config{InsecureSkipVerify: true}
}
