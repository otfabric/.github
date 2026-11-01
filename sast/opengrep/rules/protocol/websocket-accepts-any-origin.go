package fixture

import (
	"net/http"

	"github.com/gorilla/websocket"
)

// ruleid: otfabric-websocket-accepts-any-origin
var vulnerable = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

func vulnerableAssigned(u *websocket.Upgrader) {
	// ruleid: otfabric-websocket-accepts-any-origin
	u.CheckOrigin = func(r *http.Request) bool { return true }
}

// ok: otfabric-websocket-accepts-any-origin
var safe = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool {
	return r.Header.Get("Origin") == "https://hmi.example"
}}
