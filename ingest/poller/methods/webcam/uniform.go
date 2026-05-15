package webcam

import (
	"fmt"
	"time"

	"voria2ingest/types"
)

type WebcamResponse struct {
	ImageURL  string `json:"image_url"`
	ImageData []byte
}

func TransformToUniform(cameraID string, vendorData interface{}) (*types.WebcamData, error) {
	data, ok := vendorData.(*WebcamResponse)
	if !ok {
		return nil, fmt.Errorf("invalid vendor data type")
	}

	return &types.WebcamData{
		ID:        cameraID,
		Timestamp: time.Now(),
		ImageData: data.ImageData,
		ImageURL:  data.ImageURL,
	}, nil
}
