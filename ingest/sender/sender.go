package sender

import (
	"context"
	"fmt"
	"log"

	client "voria2ingest/client"
	"voria2ingest/types"
)

type Sender interface {
	Send(ctx context.Context, destinationKey string, dataType string, data interface{}) error
}

type HTTPSender struct {
	destinationClient *client.Client
	retries           int
}

func NewHTTPSender(baseURL string, retries int) *HTTPSender {
	return &HTTPSender{
		destinationClient: client.NewClient(baseURL),
		retries:           retries,
	}
}

func (s *HTTPSender) Send(ctx context.Context, destinationKey string, dataType string, data interface{}) error {
	var lastErr error

	for i := 0; i < s.retries; i++ {
		switch dataType {
		case "weather":
			err := s.sendJSON(ctx, destinationKey, data)
			if err == nil {
				return nil
			}
			lastErr = err
		case "webcam":
			err := s.sendBinary(ctx, destinationKey, data)
			if err == nil {
				return nil
			}
			lastErr = err
		default:
			return fmt.Errorf("unsupported data type: %s", dataType)
		}
	}

	return lastErr
}

func (s *HTTPSender) sendJSON(ctx context.Context, destinationKey string, data interface{}) error {
	weatherData, ok := data.(*types.WeatherStationData)
	if !ok {
		return fmt.Errorf("invalid weather data type")
	}

	batch := make([]map[string]any, len(weatherData.Measurements))
	for i, m := range weatherData.Measurements {
		batch[i] = map[string]any{
			"sensor":        m.Sensor,
			"timestamp":     m.Timestamp,
			"value":         m.Value,
			"u":             m.U,
			"v":             m.V,
			"gust":          m.Gust,
			"cumulative_mm": m.CumulativeMM,
		}
	}

	result, err := s.destinationClient.BulkPost(destinationKey, batch)
	if err != nil {
		return err
	}

	log.Printf("Successfully sent %d measurements", result.Count)

	for _, item := range result.Results {
		if !item.OK {
			log.Printf("Measurement index %d failed: %s", item.Index, item.Error)
		}
	}

	return nil
}

func (s *HTTPSender) sendBinary(ctx context.Context, destinationKey string, data interface{}) error {
	webcamData, ok := data.(*types.WebcamData)
	if !ok {
		return fmt.Errorf("invalid webcam data type")
	}

	result, err := s.destinationClient.UploadWebcamImage(destinationKey, webcamData.ImageData)
	if err != nil {
		log.Printf("Webcam upload failed: %v", err)
		return err
	}

	log.Printf("Webcam upload succeeded - shot_id: %s, s3_key: %s, duplicate: %t",
		result.ShotID, result.S3Key, result.Duplicate)
	return nil
}
