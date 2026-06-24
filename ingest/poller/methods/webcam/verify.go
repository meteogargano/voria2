package webcam

import (
	"bytes"
	"fmt"
	"image/jpeg"
)

const minJPEGSize = 4

func VerifyJPEG(data []byte) error {
	if len(data) < minJPEGSize {
		return fmt.Errorf("image too short: %d bytes", len(data))
	}

	if data[0] != 0xff || data[1] != 0xd8 {
		return fmt.Errorf("missing JPEG SOI marker")
	}

	if data[len(data)-2] != 0xff || data[len(data)-1] != 0xd9 {
		return fmt.Errorf("missing JPEG EOI marker")
	}

	if _, err := jpeg.Decode(bytes.NewReader(data)); err != nil {
		return fmt.Errorf("incomplete or corrupt JPEG: %w", err)
	}

	return nil
}
