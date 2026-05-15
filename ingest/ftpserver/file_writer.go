package ftpserver

import (
	"context"
	"log/slog"
	"os"
	"time"
)

// UploadFunc is called when a file is successfully uploaded via FTP.
// destinationKey is the webcam API key; imageData is the raw file bytes.
type UploadFunc func(ctx context.Context, destinationKey string, imageData []byte) error

type VirtualFileWriter struct {
	name           string
	data           []byte
	closed         bool
	destinationKey string
	uploadFunc     UploadFunc
	logger         *slog.Logger
	onClose        func()
}

func NewVirtualFileWriter(name string, destinationKey string, uploadFunc UploadFunc, logger *slog.Logger, onClose func()) *VirtualFileWriter {
	return &VirtualFileWriter{
		name:           name,
		data:           make([]byte, 0, 1024*1024),
		closed:         false,
		destinationKey: destinationKey,
		uploadFunc:     uploadFunc,
		logger:         logger,
		onClose:        onClose,
	}
}

func (vf *VirtualFileWriter) Read(p []byte) (n int, err error) {
	return 0, os.ErrClosed
}

func (vf *VirtualFileWriter) Seek(offset int64, whence int) (int64, error) {
	if vf.closed {
		return 0, os.ErrClosed
	}
	// FTP uploads are sequential; support seek-to-start and seek-to-end only.
	switch whence {
	case 0:
		return offset, nil
	case 2:
		return int64(len(vf.data)), nil
	default:
		return 0, os.ErrInvalid
	}
}

func (vf *VirtualFileWriter) ReadAt(p []byte, off int64) (n int, err error) {
	return 0, os.ErrClosed
}

func (vf *VirtualFileWriter) Write(p []byte) (n int, err error) {
	if vf.closed {
		return 0, os.ErrClosed
	}
	vf.data = append(vf.data, p...)
	return len(p), nil
}

func (vf *VirtualFileWriter) WriteAt(p []byte, off int64) (n int, err error) {
	if vf.closed {
		return 0, os.ErrClosed
	}
	if off != int64(len(vf.data)) {
		vf.logger.Warn("FTP upload with non-sequential offset, ignoring offset",
			slog.String("filename", vf.name),
			slog.Int64("requested_offset", off),
			slog.Int64("current_size", int64(len(vf.data))),
		)
	}
	vf.data = append(vf.data, p...)
	return len(p), nil
}

func (vf *VirtualFileWriter) WriteString(s string) (ret int, err error) {
	if vf.closed {
		return 0, os.ErrClosed
	}
	vf.data = append(vf.data, s...)
	return len(s), nil
}

func (vf *VirtualFileWriter) Close() error {
	if vf.closed {
		return nil
	}

	vf.closed = true
	fileData := vf.data
	fileSize := int64(len(fileData))

	vf.logger.Info("FTP file upload completed",
		slog.String("filename", vf.name),
		slog.Int("final_size", len(fileData)),
	)

	shouldAccept, reason := ShouldAcceptFile(vf.name, fileSize)
	if !shouldAccept {
		vf.logger.Warn("FTP file rejected by filter",
			slog.String("filename", vf.name),
			slog.String("reason", reason),
		)
		if vf.onClose != nil {
			vf.onClose()
		}
		return nil
	}

	if vf.uploadFunc != nil {
		if err := vf.uploadFunc(context.Background(), vf.destinationKey, fileData); err != nil {
			vf.logger.Error("FTP file upload to webcam API failed",
				slog.String("filename", vf.name),
				slog.String("destination_key", vf.destinationKey),
				slog.Any("error", err),
			)
			if vf.onClose != nil {
				vf.onClose()
			}
			return err
		}
		vf.logger.Info("FTP file forwarded to webcam API successfully",
			slog.String("filename", vf.name),
		)
	}

	if vf.onClose != nil {
		vf.onClose()
	}
	return nil
}

func (vf *VirtualFileWriter) Name() string {
	return vf.name
}

func (vf *VirtualFileWriter) Readdir(count int) ([]os.FileInfo, error) {
	return nil, os.ErrClosed
}

func (vf *VirtualFileWriter) Readdirnames(n int) ([]string, error) {
	return nil, os.ErrClosed
}

func (vf *VirtualFileWriter) Stat() (os.FileInfo, error) {
	return &fileInfo{
		name:    vf.name,
		size:    int64(len(vf.data)),
		mode:    os.FileMode(0644),
		modTime: time.Now(),
	}, nil
}

func (vf *VirtualFileWriter) Sync() error {
	return nil
}

func (vf *VirtualFileWriter) Truncate(size int64) error {
	if vf.closed {
		return os.ErrClosed
	}
	if size > int64(len(vf.data)) {
		// Zero-extend to reach the requested size.
		diff := size - int64(len(vf.data))
		vf.data = append(vf.data, make([]byte, diff)...)
	} else {
		vf.data = vf.data[:size]
	}
	return nil
}

type fileInfo struct {
	name    string
	size    int64
	mode    os.FileMode
	modTime time.Time
}

func (fi *fileInfo) Name() string       { return fi.name }
func (fi *fileInfo) Size() int64        { return fi.size }
func (fi *fileInfo) Mode() os.FileMode  { return fi.mode }
func (fi *fileInfo) ModTime() time.Time { return fi.modTime }
func (fi *fileInfo) IsDir() bool        { return fi.mode&0170000 != 0 }
func (fi *fileInfo) Sys() any           { return nil }
