package fixture

import (
	"encoding/binary"
	"errors"
)

const maxFrame = 1 << 16

func vulnerable(b []byte) ([]byte, []byte) {
	// ruleid: otfabric-wire-length-unchecked-make
	x := make([]byte, binary.BigEndian.Uint32(b))
	// ruleid: otfabric-wire-length-unchecked-make
	y := make([]byte, 0, int(binary.LittleEndian.Uint64(b)))
	return x, y
}

func safe(b []byte) ([]byte, error) {
	n := binary.BigEndian.Uint32(b)
	if n > maxFrame {
		return nil, errors.New("frame too long")
	}
	// ok: otfabric-wire-length-unchecked-make
	out := make([]byte, n)
	// ok: otfabric-wire-length-unchecked-make
	_ = make([]byte, binary.BigEndian.Uint16(b))
	return out, nil
}
