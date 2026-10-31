package fixture

import (
	"context"
	"fmt"
	"os/exec"
)

func vulnerable(ctx context.Context, host string) {
	// ruleid: otfabric-exec-shell-dynamic
	_ = exec.Command("sh", "-c", "ping "+host).Run()
	// ruleid: otfabric-exec-shell-dynamic
	_ = exec.CommandContext(ctx, "/bin/bash", "-c", fmt.Sprintf("ping %s", host)).Run()
}

func safe(host string) {
	// ok: otfabric-exec-shell-dynamic
	_ = exec.Command("ping", "-c", "1", host).Run()
	// ok: otfabric-exec-shell-dynamic
	_ = exec.Command("sh", "-c", "ip link show").Run()
}
