package fixture

import (
	"crypto/tls"
	"crypto/x509"
	"errors"
)

func vulnerable() *tls.Config {
	// ruleid: otfabric-tls-verify-callback-accepts-all
	return &tls.Config{VerifyPeerCertificate: func(raw [][]byte, chains [][]*x509.Certificate) error { return nil }}
}

func vulnerableAssigned(c *tls.Config) {
	// ruleid: otfabric-tls-verify-callback-accepts-all
	c.VerifyConnection = func(s tls.ConnectionState) error { return nil }
}

func safe() *tls.Config {
	// ok: otfabric-tls-verify-callback-accepts-all
	return &tls.Config{VerifyPeerCertificate: func(raw [][]byte, chains [][]*x509.Certificate) error {
		if len(chains) == 0 {
			return errors.New("no verified chain")
		}
		return nil
	}}
}
