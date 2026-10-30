// Package lowcov is a fixture of the go-ci selftest: low coverage.
package lowcov

// Tested is covered.
func Tested() int { return 1 }

// Untested is not covered.
func Untested(a int) int {
	if a > 0 {
		return a * 2
	}
	if a < 0 {
		return a * 3
	}
	return 0
}
