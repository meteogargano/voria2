package ftpserver

import (
	"io/fs"
	"log/slog"
	"os"
	"time"

	"github.com/spf13/afero"
)

type VirtualFileSystem struct {
	afero.Fs
	logger *slog.Logger
}

func NewVirtualFileSystem(logger *slog.Logger) *VirtualFileSystem {
	return &VirtualFileSystem{
		Fs:     afero.NewMemMapFs(),
		logger: logger,
	}
}

func (vfs *VirtualFileSystem) Stat(name string) (os.FileInfo, error) {
	vfs.logger.Info("Virtual filesystem stat requested", slog.String("path", name))
	return &VirtualFileInfo{
		name:    name,
		mode:    fs.ModeDir | 0755,
		size:    0,
		modTime: time.Now(),
	}, nil
}

func (vfs *VirtualFileSystem) LstatIfPossible(name string) (os.FileInfo, error) {
	return vfs.Stat(name)
}

func (vfs *VirtualFileSystem) ReadDir(name string) ([]os.FileInfo, error) {
	vfs.logger.Info("Virtual filesystem read dir requested", slog.String("path", name))
	return []os.FileInfo{}, nil
}

func (vfs *VirtualFileSystem) OpenFile(name string, flag int, perm os.FileMode) (afero.File, error) {
	vfs.logger.Info("Virtual filesystem open file requested", slog.String("path", name), slog.Int("flag", flag))

	if flag&os.O_CREATE != 0 {
		// destinationKey and uploadFunc are patched by ClientHandler.OpenFile after creation.
		return NewVirtualFileWriter(name, "", nil, vfs.logger, nil), nil
	}

	return nil, os.ErrNotExist
}

type VirtualFileInfo struct {
	name    string
	size    int64
	mode    os.FileMode
	modTime time.Time
}

func (fi *VirtualFileInfo) Name() string       { return fi.name }
func (fi *VirtualFileInfo) Size() int64        { return fi.size }
func (fi *VirtualFileInfo) Mode() os.FileMode  { return fi.mode }
func (fi *VirtualFileInfo) ModTime() time.Time { return fi.modTime }
func (fi *VirtualFileInfo) IsDir() bool        { return fi.mode&fs.ModeDir != 0 }
func (fi *VirtualFileInfo) Sys() any           { return nil }
