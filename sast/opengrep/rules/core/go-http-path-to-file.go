package fixture

import (
	"net/http"
	"os"
	"path/filepath"
)

func vulnerable(w http.ResponseWriter, r *http.Request) {
	// ruleid: otfabric-go-http-path-to-file
	p := filepath.Join("/srv/files", r.URL.Query().Get("name"))
	// ruleid: otfabric-go-http-path-to-file
	b, _ := os.ReadFile(r.FormValue("file"))
	_, _ = w.Write(append([]byte(p), b...))
}

func safe(w http.ResponseWriter, r *http.Request) {
	// ok: otfabric-go-http-path-to-file
	b, _ := os.ReadFile(filepath.Join("/srv/files", "index.html"))
	_, _ = w.Write(b)
}
