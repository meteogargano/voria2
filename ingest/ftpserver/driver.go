package ftpserver

import (
	"crypto/tls"
	"fmt"
	"log/slog"
	"strconv"

	ftpserverlib "github.com/fclairamb/ftpserverlib"
	"voria2ingest/config"
)

type ServerDriver struct {
	cfg           *config.FTPServerConfig
	authenticator *Authenticator
	uploadFunc    UploadFunc
	logger        *slog.Logger
}

func NewServerDriver(
	cfg *config.FTPServerConfig,
	credentials map[string]WebcamEntry,
	uploadFunc UploadFunc,
	logger *slog.Logger,
) *ServerDriver {
	return &ServerDriver{
		cfg:           cfg,
		authenticator: NewAuthenticator(credentials, logger),
		uploadFunc:    uploadFunc,
		logger:        logger,
	}
}

func (sd *ServerDriver) GetSettings() (*ftpserverlib.Settings, error) {
	sd.logger.Info("FTP server configured",
		slog.Int("port", sd.cfg.Port),
		slog.String("public_host", sd.cfg.PublicHost),
		slog.Int("passive_port_start", sd.cfg.PassivePortStart),
		slog.Int("passive_port_end", sd.cfg.PassivePortEnd),
	)

	return &ftpserverlib.Settings{
		ListenAddr: fmt.Sprintf(":%d", sd.cfg.Port),
		PublicHost: sd.cfg.PublicHost,
		PassiveTransferPortRange: &ftpserverlib.PortRange{
			Start: sd.cfg.PassivePortStart,
			End:   sd.cfg.PassivePortEnd,
		},
		IdleTimeout:            300,
		ConnectionTimeout:      30,
		DisableMLSD:            false,
		DisableMLST:            false,
		DisableLISTArgs:        true,
		DisableSite:            true,
		DisableActiveMode:      false,
		TLSRequired:            ftpserverlib.ClearOrEncrypted,
		PasvConnectionsCheck:   ftpserverlib.IPMatchDisabled,
		ActiveConnectionsCheck: ftpserverlib.IPMatchDisabled,
	}, nil
}

func (sd *ServerDriver) ClientConnected(cc ftpserverlib.ClientContext) (string, error) {
	sd.logger.Info("FTP client connected",
		slog.String("remote_addr", cc.RemoteAddr().String()),
		slog.String("client_id", strconv.FormatUint(uint64(cc.ID()), 10)),
	)
	return "220 Voria2Ingest FTP Server - Ready", nil
}

func (sd *ServerDriver) ClientDisconnected(cc ftpserverlib.ClientContext) {
	sd.logger.Info("FTP client disconnected",
		slog.String("remote_addr", cc.RemoteAddr().String()),
		slog.String("client_id", strconv.FormatUint(uint64(cc.ID()), 10)),
	)
}

func (sd *ServerDriver) AuthUser(cc ftpserverlib.ClientContext, user, pass string) (ftpserverlib.ClientDriver, error) {
	sd.logger.Info("FTP authentication attempt",
		slog.String("username", user),
		slog.String("remote_addr", cc.RemoteAddr().String()),
		slog.String("client_id", strconv.FormatUint(uint64(cc.ID()), 10)),
	)

	result := sd.authenticator.Authenticate(user, pass)
	if !result.Success {
		sd.logger.Warn("FTP authentication failed",
			slog.String("username", user),
			slog.String("remote_addr", cc.RemoteAddr().String()),
			slog.String("error", result.Error),
		)
		return nil, fmt.Errorf("authentication failed: %s", result.Error)
	}

	sd.logger.Info("FTP authentication successful",
		slog.String("username", user),
		slog.String("webcam_name", result.WebcamName),
		slog.String("remote_addr", cc.RemoteAddr().String()),
	)

	handler := NewClientHandler(user, result.DestinationKey, sd.uploadFunc, sd.logger)
	return handler, nil
}

func (sd *ServerDriver) GetTLSConfig() (*tls.Config, error) {
	return nil, fmt.Errorf("TLS is not configured")
}
