package lowcov

import "testing"

func TestTested(t *testing.T) {
	if Tested() != 1 {
		t.Fatal("Tested")
	}
}
