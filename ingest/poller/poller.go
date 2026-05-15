package poller

import "context"

type Poller interface {
	Name() string
	ValidateSettings(settings map[string]interface{}) error
	InitFromSettings(settings map[string]interface{}) error
	Poll(ctx context.Context) (interface{}, error)
	Transform(rawData interface{}) (interface{}, error)
}
