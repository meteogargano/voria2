package config

import (
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	DestinationAPI DestinationAPIConfig `yaml:"destinationApi"`
	Stations       []StationConfig      `yaml:"stations"`
	Webcams        []WebcamConfig       `yaml:"webcams"`
	HealthCheck    HealthCheckConfig    `yaml:"healthCheck"`
	FTPServer      FTPServerConfig      `yaml:"ftpServer"`
}

type DestinationAPIConfig struct {
	URL     string        `yaml:"url"`
	Timeout time.Duration `yaml:"timeout"`
	Retries int           `yaml:"retries"`
}

type StationConfig struct {
	Name            string                 `yaml:"name"`
	Method          string                 `yaml:"method"`
	PollingInterval time.Duration          `yaml:"pollingInterval"`
	DestinationKey  string                 `yaml:"destinationKey"`
	MethodSettings  map[string]interface{} `yaml:"methodSettings"`
}

type WebcamConfig struct {
	Name            string                 `yaml:"name"`
	Method          string                 `yaml:"method"`
	PollingInterval time.Duration          `yaml:"pollingInterval"`
	DestinationKey  string                 `yaml:"destinationKey"`
	MethodSettings  map[string]interface{} `yaml:"methodSettings"`
}

type HealthCheckConfig struct {
	Enabled bool   `yaml:"enabled"`
	Port    int    `yaml:"port"`
	Path    string `yaml:"path"`
}

type FTPServerConfig struct {
	Port             int    `yaml:"port"`
	PublicHost       string `yaml:"publicHost"`
	PassivePortStart int    `yaml:"passivePortStart"`
	PassivePortEnd   int    `yaml:"passivePortEnd"`
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	return &cfg, nil
}

func (c *Config) Validate() error {
	if err := c.DestinationAPI.Validate(); err != nil {
		return fmt.Errorf("destination API config invalid: %w", err)
	}

	for i, station := range c.Stations {
		if err := station.Validate(); err != nil {
			return fmt.Errorf("station[%d] invalid: %w", i, err)
		}
	}

	for i, webcam := range c.Webcams {
		if err := webcam.Validate(); err != nil {
			return fmt.Errorf("webcam[%d] invalid: %w", i, err)
		}
	}

	hasFTPWebcam := false
	for _, webcam := range c.Webcams {
		if webcam.Method == "ftp" {
			hasFTPWebcam = true
			break
		}
	}
	if hasFTPWebcam {
		if err := c.FTPServer.Validate(); err != nil {
			return fmt.Errorf("ftpServer config invalid: %w", err)
		}
	}

	if c.HealthCheck.Enabled {
		if err := c.HealthCheck.Validate(); err != nil {
			return fmt.Errorf("health check config invalid: %w", err)
		}
	}

	return nil
}

func (d *DestinationAPIConfig) Validate() error {
	if d.URL == "" {
		return fmt.Errorf("url is required")
	}
	if d.Timeout == 0 {
		d.Timeout = 30 * time.Second
	}
	if d.Retries == 0 {
		d.Retries = 3
	}
	return nil
}

func (s *StationConfig) Validate() error {
	if s.Name == "" {
		return fmt.Errorf("name is required")
	}
	if s.Method == "" {
		return fmt.Errorf("method is required")
	}
	if s.PollingInterval == 0 {
		return fmt.Errorf("pollingInterval is required")
	}
	if s.DestinationKey == "" {
		return fmt.Errorf("destinationKey is required")
	}
	return nil
}

func (w *WebcamConfig) Validate() error {
	if w.Name == "" {
		return fmt.Errorf("name is required")
	}
	if w.Method == "" {
		return fmt.Errorf("method is required")
	}
	if w.Method != "ftp" && w.PollingInterval == 0 {
		return fmt.Errorf("pollingInterval is required")
	}
	if w.DestinationKey == "" {
		return fmt.Errorf("destinationKey is required")
	}
	return nil
}

func (h *HealthCheckConfig) Validate() error {
	if h.Port == 0 {
		h.Port = 8080
	}
	if h.Path == "" {
		h.Path = "/health"
	}
	return nil
}

func (f *FTPServerConfig) Validate() error {
	if f.Port == 0 {
		return fmt.Errorf("port is required")
	}
	if f.PublicHost == "" {
		return fmt.Errorf("publicHost is required")
	}
	if f.PassivePortStart == 0 {
		f.PassivePortStart = 30000
	}
	if f.PassivePortEnd == 0 {
		f.PassivePortEnd = 30010
	}
	return nil
}
