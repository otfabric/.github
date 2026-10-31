package fixture

import (
	"encoding/json"
	"io"
	"net/http"
)

func vulnerable(w http.ResponseWriter, r *http.Request) {
	// ruleid: otfabric-http-body-unbounded-read
	b, _ := io.ReadAll(r.Body)
	_, _ = w.Write(b)
}

func vulnerableJSON(w http.ResponseWriter, r *http.Request) {
	var v any
	// ruleid: otfabric-http-body-unbounded-read
	_ = json.NewDecoder(r.Body).Decode(&v)
}

func safe(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	// ok: otfabric-http-body-unbounded-read
	b, _ := io.ReadAll(r.Body)
	_, _ = w.Write(b)
}

func safeClient(resp *http.Response) {
	// ok: otfabric-http-body-unbounded-read
	_, _ = io.ReadAll(io.LimitReader(resp.Body, 1<<20))
}
