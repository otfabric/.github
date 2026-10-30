package pass

import "testing"

func TestSum(t *testing.T) {
	if Sum(1, 2) != 3 {
		t.Fatal("Sum")
	}
}

func TestBoth(t *testing.T) {
	ok := func() error { return nil }
	if err := Both(ok, ok); err != nil {
		t.Fatal(err)
	}
}

func FuzzSum(f *testing.F) {
	f.Add(1, 2)
	f.Fuzz(func(t *testing.T, a, b int) {
		if Sum(a, b) != Sum(b, a) {
			t.Fatal("not commutative")
		}
	})
}
