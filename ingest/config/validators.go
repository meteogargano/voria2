package config

import "fmt"

type MethodValidator interface {
	ValidateSettings(settings map[string]interface{}) error
}

func ValidateMethodSettings(method string, settings map[string]interface{}) error {
	switch method {
	case "anemos":
		return validateAnemosSettings(settings)
	case "clientraw":
		return validateClientrawSettings(settings)
	case "meteobridge":
		return validateMeteobridgeSettings(settings)
	case "weatherlinklive":
		return validateWeatherlinkliveSettings(settings)
	case "simple-http":
		return validateSimpleHTTPSettings(settings)
	case "ftp":
		return validateFTPWebcamSettings(settings)
	default:
		return fmt.Errorf("unknown method: %s", method)
	}
}

func validateAnemosSettings(settings map[string]interface{}) error {
	if _, ok := settings["url"]; !ok {
		return fmt.Errorf("url is required")
	}
	return nil
}

func validateClientrawSettings(settings map[string]interface{}) error {
	if _, ok := settings["url"]; !ok {
		return fmt.Errorf("url is required")
	}
	return nil
}

func validateMeteobridgeSettings(settings map[string]interface{}) error {
	if _, ok := settings["url"]; !ok {
		return fmt.Errorf("url is required")
	}
	return nil
}

func validateSimpleHTTPSettings(settings map[string]interface{}) error {
	if _, ok := settings["url"]; !ok {
		return fmt.Errorf("url is required")
	}
	return nil
}

func validateWeatherlinkliveSettings(settings map[string]interface{}) error {
	if _, ok := settings["stationId"]; !ok {
		return fmt.Errorf("stationId is required")
	}
	if _, ok := settings["apiKey"]; !ok {
		return fmt.Errorf("apiKey is required")
	}
	if _, ok := settings["apiSecret"]; !ok {
		return fmt.Errorf("apiSecret is required")
	}
	if _, ok := settings["baroCalibrationOffset"]; !ok {
		return fmt.Errorf("baroCalibrationOffset is required")
	}
	return nil
}

func validateFTPWebcamSettings(settings map[string]interface{}) error {
	if _, ok := settings["username"]; !ok {
		return fmt.Errorf("username is required")
	}
	if _, ok := settings["password"]; !ok {
		return fmt.Errorf("password is required")
	}
	return nil
}
