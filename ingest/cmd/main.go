package main

import (
	"context"
	"fmt"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	voriaapi "voria2ingest/client"
	"voria2ingest/config"
	"voria2ingest/ftpserver"
	"voria2ingest/scheduler"
	"voria2ingest/sender"
)

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Usage: voria2ingest <config-file>")
	}

	cfgPath := os.Args[1]
	cfg, err := config.Load(cfgPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	if err := cfg.Validate(); err != nil {
		log.Fatalf("Invalid config: %v", err)
	}

	destinationClient := voriaapi.NewClient(cfg.DestinationAPI.URL)

	if err := verifyStationKeys(destinationClient, cfg); err != nil {
		log.Printf("Warning: Some station key verifications failed: %v", err)
	}

	if err := verifyWebcamKeys(destinationClient, cfg); err != nil {
		log.Printf("Warning: Some webcam key verifications failed: %v", err)
	}

	s := sender.NewHTTPSender(cfg.DestinationAPI.URL, cfg.DestinationAPI.Retries)

	sched, err := scheduler.NewScheduler(cfg, s)
	if err != nil {
		log.Fatalf("Failed to create scheduler: %v", err)
	}

	// Start FTP server if any webcam uses method "ftp".
	var ftpSrv *ftpserver.Server
	ftpCredentials := buildFTPCredentials(cfg)
	if len(ftpCredentials) > 0 {
		logger := slog.New(slog.NewTextHandler(os.Stdout, nil))
		uploadFunc := func(ctx context.Context, destinationKey string, imageData []byte) error {
			_, err := destinationClient.UploadWebcamImage(destinationKey, imageData)
			return err
		}
		ftpSrv = ftpserver.NewServer(&cfg.FTPServer, ftpCredentials, uploadFunc, logger)
		go func() {
			if err := ftpSrv.Start(); err != nil {
				log.Printf("FTP server error: %v", err)
			}
		}()
	}

	if cfg.HealthCheck.Enabled {
		go startHealthCheck(cfg.HealthCheck.Port, cfg.HealthCheck.Path, sched)
	}

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	sched.Start()

	log.Println("Scheduler started. Press Ctrl+C to stop.")

	<-sigChan

	if ftpSrv != nil {
		if err := ftpSrv.Stop(); err != nil {
			log.Printf("FTP server stop error: %v", err)
		}
	}

	sched.Stop()
	log.Println("Shutdown complete")
}

// buildFTPCredentials extracts FTP webcam configs and returns the credential map.
func buildFTPCredentials(cfg *config.Config) map[string]ftpserver.WebcamEntry {
	credentials := make(map[string]ftpserver.WebcamEntry)
	for _, webcam := range cfg.Webcams {
		if webcam.Method != "ftp" {
			continue
		}
		username, _ := webcam.MethodSettings["username"].(string)
		password, _ := webcam.MethodSettings["password"].(string)
		if username == "" || password == "" {
			log.Printf("Warning: FTP webcam '%s' has missing username or password — skipping", webcam.Name)
			continue
		}
		if _, exists := credentials[username]; exists {
			log.Fatalf("Duplicate FTP username '%s' found in webcam configs — usernames must be unique", username)
		}
		credentials[username] = ftpserver.WebcamEntry{
			Password:       password,
			DestinationKey: webcam.DestinationKey,
			Name:           webcam.Name,
		}
		log.Printf("Registered FTP webcam '%s' with username '%s'", webcam.Name, username)
	}
	return credentials
}

func startHealthCheck(port int, path string, sched *scheduler.Scheduler) {
	http.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"healthy"}`)
	})

	log.Printf("Health check server listening on :%d%s", port, path)
	if err := http.ListenAndServe(fmt.Sprintf(":%d", port), nil); err != nil {
		log.Printf("Health check server error: %v", err)
	}
}

func verifyStationKeys(apiClient *voriaapi.Client, cfg *config.Config) error {
	var verificationErrors []error

	for _, station := range cfg.Stations {
		stationName, err := apiClient.VerifyKey(station.DestinationKey)
		if err != nil {
			log.Printf("Warning: Failed to verify station '%s' key: %v", station.Name, err)
			verificationErrors = append(verificationErrors, fmt.Errorf("station '%s': %w", station.Name, err))
		} else {
			log.Printf("Verified station '%s' key - API reports station name: %s", station.Name, stationName)
		}
	}

	if len(verificationErrors) > 0 {
		return fmt.Errorf("%d station(s) failed verification", len(verificationErrors))
	}

	return nil
}

func verifyWebcamKeys(apiClient *voriaapi.Client, cfg *config.Config) error {
	var verificationErrors []error

	for _, webcam := range cfg.Webcams {
		webcamName, err := apiClient.VerifyWebcamKey(webcam.DestinationKey)
		if err != nil {
			log.Printf("Warning: Failed to verify webcam '%s' key: %v", webcam.Name, err)
			verificationErrors = append(verificationErrors, fmt.Errorf("webcam '%s': %w", webcam.Name, err))
		} else {
			log.Printf("Verified webcam '%s' key - API reports webcam name: %s", webcam.Name, webcamName)
		}
	}

	if len(verificationErrors) > 0 {
		return fmt.Errorf("%d webcam(s) failed verification", len(verificationErrors))
	}

	return nil
}
