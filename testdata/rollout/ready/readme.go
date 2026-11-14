package ready

import "os"

func readme() ([]byte, error) { return os.ReadFile("README.md") }
