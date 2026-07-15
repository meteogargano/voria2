package webcam

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"strings"
	"testing"
)

func encodeTestJPEG(t *testing.T, width, height int) []byte {
	t.Helper()

	img := image.NewRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			img.SetRGBA(x, y, color.RGBA{R: uint8(x % 256), G: uint8(y % 256), B: uint8((x + y) % 256), A: 255})
		}
	}

	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 80}); err != nil {
		t.Fatalf("failed to encode test JPEG: %v", err)
	}

	return buf.Bytes()
}

func TestVerifyJPEGAcceptsCompleteImage(t *testing.T) {
	data := encodeTestJPEG(t, 16, 16)

	if err := VerifyJPEG(data); err != nil {
		t.Fatalf("expected valid JPEG to pass, got error: %v", err)
	}
}

func TestVerifyJPEGRejectsTruncatedScan(t *testing.T) {
	data := encodeTestJPEG(t, 64, 64)

	truncated := data[:len(data)/2]

	err := VerifyJPEG(truncated)
	if err == nil {
		t.Fatal("expected truncated JPEG to fail verification")
	}
}

func TestVerifyJPEGRejectsCorruptScanData(t *testing.T) {
	data := make([]byte, len(encodeTestJPEG(t, 64, 64)))
	copy(data, encodeTestJPEG(t, 64, 64))

	mid := len(data) / 2
	for i := mid; i < len(data)-2; i++ {
		data[i] = 0x00
	}

	err := VerifyJPEG(data)
	if err == nil {
		t.Fatal("expected corrupt scan data to fail verification")
	}
	if !strings.Contains(err.Error(), "incomplete or corrupt JPEG") {
		t.Fatalf("expected decode error message, got: %v", err)
	}
}

func TestVerifyJPEGRejectsMissingSOI(t *testing.T) {
	data := encodeTestJPEG(t, 8, 8)
	data[0] = 0x00
	data[1] = 0x00

	err := VerifyJPEG(data)
	if err == nil || !strings.Contains(err.Error(), "SOI") {
		t.Fatalf("expected SOI error, got: %v", err)
	}
}

func TestVerifyJPEGRejectsMissingEOI(t *testing.T) {
	data := encodeTestJPEG(t, 8, 8)
	data[len(data)-1] = 0x00

	err := VerifyJPEG(data)
	if err == nil || !strings.Contains(err.Error(), "EOI") {
		t.Fatalf("expected EOI error, got: %v", err)
	}
}

func TestVerifyJPEGRejectsTooShort(t *testing.T) {
	if err := VerifyJPEG([]byte{0xff, 0xd8}); err == nil {
		t.Fatal("expected too-short data to fail")
	}

	if err := VerifyJPEG(nil); err == nil {
		t.Fatal("expected nil data to fail")
	}
}
