// Package greet is the fixture of the docs-check selftest: its documents
// name a function it does not have, so docsync reports a finding.
package greet

// Hello returns a greeting for name.
func Hello(name string) string { return "hello, " + name }
