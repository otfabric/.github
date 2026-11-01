package fixture

import "github.com/golang-jwt/jwt/v5"

func vulnerable() *jwt.Token {
	// ruleid: otfabric-go-auth-none-accepted
	return jwt.New(jwt.SigningMethodNone)
}

func vulnerableKey() any {
	// ruleid: otfabric-go-auth-none-accepted
	return jwt.UnsafeAllowNoneSignatureType
}

func safe() *jwt.Token {
	// ok: otfabric-go-auth-none-accepted
	return jwt.New(jwt.SigningMethodES256)
}
