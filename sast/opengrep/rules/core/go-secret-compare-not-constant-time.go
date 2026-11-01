package fixture

import "crypto/subtle"

type creds struct{ Password string }

func vulnerable(c creds, given, secret string) bool {
	// ruleid: otfabric-go-secret-compare-not-constant-time
	if given == c.Password {
		return true
	}
	// ruleid: otfabric-go-secret-compare-not-constant-time
	return secret == given
}

func safe(c creds, given string) bool {
	// ok: otfabric-go-secret-compare-not-constant-time
	if c.Password == "" {
		return false
	}
	// ok: otfabric-go-secret-compare-not-constant-time
	return subtle.ConstantTimeCompare([]byte(given), []byte(c.Password)) == 1
}
