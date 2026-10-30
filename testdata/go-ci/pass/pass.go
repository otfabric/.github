// Package pass is a fixture of the go-ci selftest: full coverage, a fuzz target.
package pass

import "golang.org/x/sync/errgroup"

// Sum adds a and b.
func Sum(a, b int) int { return a + b }

// Both runs f and g concurrently.
func Both(f, g func() error) error {
	var eg errgroup.Group
	eg.Go(f)
	eg.Go(g)
	return eg.Wait()
}
