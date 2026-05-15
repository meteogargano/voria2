package scheduler

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"sync"
	"time"

	"voria2ingest/config"
	"voria2ingest/poller"
	"voria2ingest/sender"
)

type Scheduler struct {
	jobs       []Job
	ctx        context.Context
	cancel     context.CancelFunc
	wg         sync.WaitGroup
	workerPool chan struct{}
}

func NewScheduler(cfg *config.Config, s sender.Sender) (*Scheduler, error) {
	ctx, cancel := context.WithCancel(context.Background())

	scheduler := &Scheduler{
		ctx:        ctx,
		cancel:     cancel,
		workerPool: make(chan struct{}, 10),
	}

	for _, station := range cfg.Stations {
		p, err := poller.GetPoller(station.Method)
		if err != nil {
			cancel()
			return nil, fmt.Errorf("failed to get poller for station %s: %w", station.Name, err)
		}

		if err := p.ValidateSettings(station.MethodSettings); err != nil {
			cancel()
			return nil, fmt.Errorf("failed to validate settings for station %s: %w", station.Name, err)
		}

		if err := p.InitFromSettings(station.MethodSettings); err != nil {
			cancel()
			return nil, fmt.Errorf("failed to init settings for station %s: %w", station.Name, err)
		}

		job := NewBaseJob(station.Name, p, s, station.PollingInterval, station.DestinationKey, "weather")
		scheduler.jobs = append(scheduler.jobs, job)
	}

	for _, webcam := range cfg.Webcams {
		if webcam.Method == "ftp" {
			if webcam.PollingInterval != 0 {
				log.Printf("Warning: webcam '%s' uses method 'ftp' — pollingInterval is ignored for FTP sources", webcam.Name)
			}
			continue
		}

		p, err := poller.GetPoller(webcam.Method)
		if err != nil {
			cancel()
			return nil, fmt.Errorf("failed to get poller for webcam %s: %w", webcam.Name, err)
		}

		if err := p.ValidateSettings(webcam.MethodSettings); err != nil {
			cancel()
			return nil, fmt.Errorf("failed to validate settings for webcam %s: %w", webcam.Name, err)
		}

		if err := p.InitFromSettings(webcam.MethodSettings); err != nil {
			cancel()
			return nil, fmt.Errorf("failed to init settings for webcam %s: %w", webcam.Name, err)
		}

		job := NewBaseJob(webcam.Name, p, s, webcam.PollingInterval, webcam.DestinationKey, "webcam")
		scheduler.jobs = append(scheduler.jobs, job)
	}

	return scheduler, nil
}

func (s *Scheduler) Start() {
	log.Printf("Starting scheduler with %d jobs", len(s.jobs))

	for _, job := range s.jobs {
		s.wg.Add(1)
		go s.runJob(job)
	}
}

func (s *Scheduler) runJob(job Job) {
	defer s.wg.Done()

	randomDelay := time.Duration(rand.Int63n(5000)) * time.Millisecond
	log.Printf("Job %s: starting with random delay: %v (interval: %v)", job.Name(), randomDelay, job.Interval())

	time.Sleep(randomDelay)

	s.workerPool <- struct{}{}
	go func() {
		defer func() { <-s.workerPool }()

		if err := job.Run(s.ctx); err != nil {
			log.Printf("Job %s: error: %v", job.Name(), err)
		}
	}()

	ticker := time.NewTicker(job.Interval())
	defer ticker.Stop()

	for {
		select {
		case <-s.ctx.Done():
			log.Printf("Job %s: stopping", job.Name())
			return
		case <-ticker.C:
			s.workerPool <- struct{}{}
			go func() {
				defer func() { <-s.workerPool }()

				if err := job.Run(s.ctx); err != nil {
					log.Printf("Job %s: error: %v", job.Name(), err)
				}
			}()
		}
	}
}

func (s *Scheduler) Stop() {
	log.Println("Stopping scheduler...")
	s.cancel()
	s.wg.Wait()
	log.Println("Scheduler stopped")
}
