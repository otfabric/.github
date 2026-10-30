// Command tool proves that go-ci tests cmd/ when told to.
package main

import "fmt"

func main() { fmt.Println(greeting()) }

func greeting() string { return "ok" }
