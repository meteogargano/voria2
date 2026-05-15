package types

import "time"

type WeatherMeasurement struct {
	Sensor       string  `json:"sensor"`
	Value        float64 `json:"value,omitempty"`
	Timestamp    string  `json:"timestamp"`
	U            float64 `json:"u,omitempty"`
	V            float64 `json:"v,omitempty"`
	Gust         float64 `json:"gust,omitempty"`
	CumulativeMM float64 `json:"cumulative_mm,omitempty"`
}

type WeatherStationData struct {
	Measurements []WeatherMeasurement `json:"-"`
	Timestamp    time.Time            `json:"-"`
}

type WebcamData struct {
	ID        string    `json:"id"`
	Timestamp time.Time `json:"timestamp"`
	ImageData []byte    `json:"-"`
	ImageURL  string    `json:"imageUrl,omitempty"`
}

type IngestPayload struct {
	SourceKey string      `json:"sourceKey"`
	Type      string      `json:"type"`
	Data      interface{} `json:"data"`
}

type IngestBinaryPayload struct {
	SourceKey string
	Type      string
	Data      []byte
}
