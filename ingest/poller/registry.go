package poller

import (
	"fmt"

	"voria2ingest/poller/methods/weather"
	"voria2ingest/poller/methods/webcam"
)

type MethodFactory func() Poller

var methodRegistry = map[string]MethodFactory{
	"anemos":          func() Poller { return &weather.AnemosWeather{} },
	"clientraw":       func() Poller { return &weather.ClientrawWeather{} },
	"meteobridge":     func() Poller { return &weather.MeteobridgeWeather{} },
	"weatherlinklive": func() Poller { return &weather.Weatherlinklive{} },
	"simple-http":     func() Poller { return &webcam.SimpleHTTPWebcam{} },
}

func RegisterMethod(name string, factory MethodFactory) {
	methodRegistry[name] = factory
}

func GetPoller(method string) (Poller, error) {
	factory, ok := methodRegistry[method]
	if !ok {
		return nil, fmt.Errorf("unknown method: %s", method)
	}
	return factory(), nil
}
