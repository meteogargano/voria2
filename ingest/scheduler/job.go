package scheduler

import (
	"context"
	"log"
	"time"

	"voria2ingest/poller"
	"voria2ingest/sender"
)

type Job interface {
	Run(ctx context.Context) error
	Interval() time.Duration
	Name() string
	Stop()
}

type BaseJob struct {
	name            string
	poller          poller.Poller
	sender          sender.Sender
	pollingInterval time.Duration
	destinationKey  string
	dataType        string
	ticker          *time.Ticker
	cancelFunc      context.CancelFunc
}

func NewBaseJob(name string, p poller.Poller, s sender.Sender, interval time.Duration, destinationKey string, dataType string) *BaseJob {
	return &BaseJob{
		name:            name,
		poller:          p,
		sender:          s,
		pollingInterval: interval,
		destinationKey:  destinationKey,
		dataType:        dataType,
	}
}

func (j *BaseJob) Run(ctx context.Context) error {
	log.Printf("Job %s: starting poll", j.name)

	rawData, err := j.poller.Poll(ctx)
	if err != nil {
		log.Printf("Job %s: poll failed: %v", j.name, err)
		return err
	}

	transformedData, err := j.poller.Transform(rawData)
	if err != nil {
		log.Printf("Job %s: transform failed: %v", j.name, err)
		return err
	}

	err = j.sender.Send(ctx, j.destinationKey, j.dataType, transformedData)
	if err != nil {
		log.Printf("Job %s: send failed: %v", j.name, err)
		return err
	}

	log.Printf("Job %s: completed successfully", j.name)
	return nil
}

func (j *BaseJob) Interval() time.Duration {
	return j.pollingInterval
}

func (j *BaseJob) Name() string {
	return j.name
}

func (j *BaseJob) Stop() {
	if j.cancelFunc != nil {
		j.cancelFunc()
	}
	if j.ticker != nil {
		j.ticker.Stop()
	}
}
