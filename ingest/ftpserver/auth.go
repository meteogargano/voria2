package ftpserver

import (
	"log/slog"
	"strings"
)

// WebcamEntry holds the FTP credentials and API routing info for a single FTP-based webcam.
type WebcamEntry struct {
	Password       string
	DestinationKey string
	Name           string
}

// Authenticator validates FTP credentials against a static config-derived credential map.
type Authenticator struct {
	// credentials maps FTP username → WebcamEntry
	credentials map[string]WebcamEntry
	logger      *slog.Logger
}

func NewAuthenticator(credentials map[string]WebcamEntry, logger *slog.Logger) *Authenticator {
	return &Authenticator{
		credentials: credentials,
		logger:      logger,
	}
}

// AuthResult is the outcome of an authentication attempt.
type AuthResult struct {
	Success        bool
	DestinationKey string
	WebcamName     string
	Error          string
}

func (a *Authenticator) Authenticate(username, password string) AuthResult {
	username = strings.TrimSpace(username)
	password = strings.TrimSpace(password)

	entry, ok := a.credentials[username]
	if !ok {
		a.logger.Info("FTP authentication failed: unknown username",
			slog.String("username", username),
		)
		return AuthResult{Success: false, Error: "invalid credentials"}
	}

	if entry.Password != password {
		a.logger.Info("FTP authentication failed: wrong password",
			slog.String("username", username),
		)
		return AuthResult{Success: false, Error: "invalid credentials"}
	}

	a.logger.Info("FTP authentication successful",
		slog.String("username", username),
		slog.String("webcam_name", entry.Name),
	)
	return AuthResult{
		Success:        true,
		DestinationKey: entry.DestinationKey,
		WebcamName:     entry.Name,
	}
}
