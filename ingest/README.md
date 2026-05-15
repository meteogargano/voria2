# Voria2Ingest

A Go-based data ingestion service that polls weather station and webcam APIs, transforms the data, and sends it to a destination API in a uniform format.

## Project Structure

```
voria2ingest/
├── cmd/
│   └── main.go                 # Application entry point
├── config/
│   ├── config.go              # Configuration loading and validation
│   └── validators.go          # Custom method-specific validators
├── scheduler/
│   ├── scheduler.go           # Main scheduler with worker pool
│   └── job.go                 # Job interface and base implementation
├── poller/
│   ├── poller.go              # Core Poller interface
│   ├── registry.go            # Method factory pattern
│   └── methods/               # Method implementations
│       ├── base.go            # Base HTTP poller
│       ├── weather/
│       │   ├── vendor_a.go    # Vendor A weather station
│       │   ├── vendor_b.go    # Vendor B weather station
│       │   └── uniform.go     # Uniform weather station model
│       └── webcam/
│           ├── provider_x.go  # Provider X webcam
│           └── uniform.go     # Uniform webcam model
├── sender/
│   └── sender.go              # Destination API sender
└── types/
    └── types.go               # Shared data structures
```

## Configuration

The application is configured via a YAML file:

```yaml
destinationApi:
  url: "http://localhost:9000/ingest"
  timeout: 30s
  retries: 3

stations:
  - name: "station-1"
    method: "vendor-a-weather"
    pollingInterval: 60s
    destinationKey: "weather-1"
    methodSettings:
      apiKey: "your-api-key"
      stationId: "station-001"
      url: "https://api.weather-a.example.com/station/001"

webcams:
  - name: "webcam-1"
    method: "provider-x-webcam"
    pollingInterval: 30s
    destinationKey: "cam-1"
    methodSettings:
      apiKey: "your-api-key"
      cameraId: "cam-001"
      url: "https://images.webcam-x.example.com/cam/001"

  - name: "camdiprova"
    method: "ftp"
    destinationKey: "vwk_4kkoyjtpPRagvP9fk0Hp4AT1L3x1gUjwfJHryeqW-bk"
    methodSettings:
      username: "camexample"
      password: "changeme"

ftpServer:
  port: 2121
  publicHost: "127.0.0.1"
  passivePortStart: 30000
  passivePortEnd: 30010

healthCheck:
  enabled: true
  port: 8080
  path: "/health"
```

## Running

```bash
# Build the application
go build -o voria2ingest ./cmd

# Run with configuration
./voria2ingest config.yaml
```

## Adding New Methods

1. Create a new file in `poller/methods/` (e.g., `weather/vendor_c.go`)
2. Implement the `Poller` interface
3. Register the method in `poller/registry.go`
4. Add validation in `config/validators.go`

## Features

- **Concurrent polling**: All jobs run in parallel with a worker pool
- **Error handling**: Jobs log errors and continue running
- **Graceful shutdown**: Responds to SIGTERM/SIGINT
- **Health checks**: Optional HTTP endpoint for monitoring
- **Extensible**: Easy to add new polling methods
