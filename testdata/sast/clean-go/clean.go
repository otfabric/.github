// SPDX-License-Identifier: MIT

// Package clean has nothing for either scanner to report.
package clean

import "strings"

// Upper returns s in upper case.
func Upper(s string) string {
	return strings.ToUpper(s)
}
