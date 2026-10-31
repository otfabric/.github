package fixture

import "net"

func vulnerable(l net.Listener) {
	for {
		c, err := l.Accept()
		if err != nil {
			return
		}
		// ruleid: otfabric-defer-in-unbounded-loop
		defer c.Close()
	}
}

func safe(l net.Listener) {
	for {
		c, err := l.Accept()
		if err != nil {
			return
		}
		func() {
			// ok: otfabric-defer-in-unbounded-loop
			defer c.Close()
		}()
	}
}

func safeGoroutine(l net.Listener) {
	for {
		c, err := l.Accept()
		if err != nil {
			return
		}
		go func() {
			// ok: otfabric-defer-in-unbounded-loop
			defer c.Close()
		}()
	}
}
