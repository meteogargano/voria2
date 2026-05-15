package ftpserver

import (
	"log/slog"

	ftpserverlib "github.com/fclairamb/ftpserverlib"
	"voria2ingest/config"
)

// Server wraps the ftpserverlib FTP server for webcam image ingestion.
type Server struct {
	ftpServer *ftpserverlib.FtpServer
	port      int
	logger    *slog.Logger
}

// NewServer creates an FTP server that accepts image uploads from configured webcam sources.
// credentials maps FTP username → WebcamEntry (password + destinationKey + name).
// uploadFunc is called with the destinationKey and raw image bytes on each successful upload.
func NewServer(
	cfg *config.FTPServerConfig,
	credentials map[string]WebcamEntry,
	uploadFunc UploadFunc,
	logger *slog.Logger,
) *Server {
	driver := NewServerDriver(cfg, credentials, uploadFunc, logger)
	return &Server{
		ftpServer: ftpserverlib.NewFtpServer(driver),
		port:      cfg.Port,
		logger:    logger,
	}
}

func (s *Server) Start() error {
	s.logger.Info("Starting FTP server", slog.Int("port", s.port))
	return s.ftpServer.ListenAndServe()
}

func (s *Server) Stop() error {
	s.logger.Info("Stopping FTP server")
	return s.ftpServer.Stop()
}
