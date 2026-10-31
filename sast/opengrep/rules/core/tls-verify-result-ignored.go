package fixture

import "crypto/x509"

func vulnerable(c, parent *x509.Certificate) {
	// ruleid: otfabric-tls-verify-result-ignored
	_, _ = c.Verify(x509.VerifyOptions{})
	// ruleid: otfabric-tls-verify-result-ignored
	_ = c.CheckSignatureFrom(parent)
}

func safe(c, parent *x509.Certificate) error {
	// ok: otfabric-tls-verify-result-ignored
	if _, err := c.Verify(x509.VerifyOptions{}); err != nil {
		return err
	}
	// ok: otfabric-tls-verify-result-ignored
	return c.CheckSignatureFrom(parent)
}
