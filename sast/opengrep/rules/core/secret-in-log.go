package fixture

import (
	"log"
	"log/slog"
)

type creds struct{ User, Password string }

func vulnerable(password string, c creds, l *slog.Logger) {
	// ruleid: otfabric-secret-in-log
	slog.Info("login", "password", password)
	// ruleid: otfabric-secret-in-log
	l.Debug("login", "pw", c.Password)
	// ruleid: otfabric-secret-in-log
	log.Printf("login %s", password)
}

func safe(c creds, l *slog.Logger) {
	// ok: otfabric-secret-in-log
	slog.Info("login", "user", c.User)
	// ok: otfabric-secret-in-log
	l.Debug("password rejected", "user", c.User)
	// ok: otfabric-secret-in-log
	log.Printf("login %s", c.User)
}
