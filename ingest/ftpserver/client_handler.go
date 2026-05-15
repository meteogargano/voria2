package ftpserver

import (
	"log/slog"
	"os"
	"time"

	"github.com/spf13/afero"
)

// ClientHandler implements ftpserverlib.ClientDriver for a single authenticated webcam session.
// All destructive FS operations silently succeed; only file writes are meaningful.
type ClientHandler struct {
	vfs            *VirtualFileSystem
	destinationKey string
	uploadFunc     UploadFunc
	username       string
	logger         *slog.Logger
}

func NewClientHandler(username string, destinationKey string, uploadFunc UploadFunc, logger *slog.Logger) *ClientHandler {
	return &ClientHandler{
		vfs:            NewVirtualFileSystem(logger),
		destinationKey: destinationKey,
		uploadFunc:     uploadFunc,
		username:       username,
		logger:         logger,
	}
}

func (ch *ClientHandler) OpenFile(name string, flag int, perm os.FileMode) (afero.File, error) {
	ch.logger.Info("Client file open requested",
		slog.String("username", ch.username),
		slog.String("filename", name),
		slog.Int("flag", flag),
	)

	file, err := ch.vfs.OpenFile(name, int(flag), perm)
	if err != nil {
		ch.logger.Error("Failed to open file",
			slog.String("username", ch.username),
			slog.String("filename", name),
			slog.Any("error", err),
		)
		return nil, err
	}

	// Patch the writer with this session's routing info.
	if vf, ok := file.(*VirtualFileWriter); ok {
		vf.destinationKey = ch.destinationKey
		vf.uploadFunc = ch.uploadFunc
	}

	return file, nil
}

func (ch *ClientHandler) Stat(name string) (os.FileInfo, error) {
	return ch.vfs.Stat(name)
}

func (ch *ClientHandler) LstatIfPossible(name string) (os.FileInfo, error) {
	return ch.vfs.LstatIfPossible(name)
}

func (ch *ClientHandler) ReadDir(name string) ([]os.FileInfo, error) {
	ch.logger.Info("Client read dir requested",
		slog.String("username", ch.username),
		slog.String("path", name),
	)
	return ch.vfs.ReadDir(name)
}

func (ch *ClientHandler) ReadDirNames(path string) ([]string, error) {
	infos, err := ch.ReadDir(path)
	if err != nil {
		return nil, err
	}
	names := make([]string, len(infos))
	for i, info := range infos {
		names[i] = info.Name()
	}
	return names, nil
}

func (ch *ClientHandler) Mkdir(name string, perm os.FileMode) error {
	ch.logger.Info("Client mkdir requested (silently succeeding)",
		slog.String("username", ch.username),
		slog.String("path", name),
	)
	return nil
}

func (ch *ClientHandler) MkdirAll(path string, perm os.FileMode) error {
	ch.logger.Info("Client mkdirall requested (silently succeeding)",
		slog.String("username", ch.username),
		slog.String("path", path),
	)
	return nil
}

func (ch *ClientHandler) Remove(name string) error {
	ch.logger.Info("Client remove requested (silently succeeding)",
		slog.String("username", ch.username),
		slog.String("path", name),
	)
	return nil
}

func (ch *ClientHandler) RemoveAll(path string) error {
	ch.logger.Info("Client removeall requested (silently succeeding)",
		slog.String("username", ch.username),
		slog.String("path", path),
	)
	return nil
}

func (ch *ClientHandler) Rename(oldname, newname string) error {
	ch.logger.Info("Client rename requested (silently succeeding)",
		slog.String("username", ch.username),
		slog.String("oldname", oldname),
		slog.String("newname", newname),
	)
	return nil
}

func (ch *ClientHandler) Chtimes(name string, atime, mtime time.Time) error {
	ch.logger.Info("Client chtimes requested (silently succeeding)",
		slog.String("username", ch.username),
		slog.String("path", name),
	)
	return nil
}

func (ch *ClientHandler) Chmod(name string, mode os.FileMode) error {
	ch.logger.Info("Client chmod requested (silently succeeding)",
		slog.String("username", ch.username),
		slog.String("path", name),
	)
	return nil
}

func (ch *ClientHandler) Chown(name string, uid, gid int) error {
	ch.logger.Info("Client chown requested (silently succeeding)",
		slog.String("username", ch.username),
		slog.String("path", name),
	)
	return nil
}

func (ch *ClientHandler) Name() string {
	return ch.username
}

func (ch *ClientHandler) Create(name string) (afero.File, error) {
	ch.logger.Info("Client create requested",
		slog.String("username", ch.username),
		slog.String("path", name),
	)
	return NewVirtualFileWriter(name, ch.destinationKey, ch.uploadFunc, ch.logger, nil), nil
}

func (ch *ClientHandler) Open(name string) (afero.File, error) {
	ch.logger.Info("Client open requested",
		slog.String("username", ch.username),
		slog.String("filename", name),
	)
	return ch.vfs.OpenFile(name, os.O_RDONLY, 0644)
}
