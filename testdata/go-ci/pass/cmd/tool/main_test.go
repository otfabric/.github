package main

import "testing"

func TestGreeting(t *testing.T) {
	if greeting() != "ok" {
		t.Fatal("greeting")
	}
}
