// SPDX-License-Identifier: MIT

// Package broken does not type-check, so a scan of it cannot be complete.
package broken

func Undefined() int { return missing() }
