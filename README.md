# Voria2

Voria2 is a Phoenix application for running MeteoGargano, a weather and webcam network. It serves the public site, stores incoming measurements and webcam shots, and provides an authenticated back office for managing installations, stations, sensors, webcams, faults, and editorial content.

## What This Repository Does

This repository contains two related parts:

- The main Elixir/Phoenix application in the project root.
- An optional Go companion service in `/ingest` that polls supported external sources and forwards data into the Phoenix app's ingest endpoints.

In the Phoenix app, the implemented surface includes:

- Public pages for the live map, station comparison, installation details, webcams, blog content, and a daily log view.
- Authenticated management pages under `/manage` for maintaining the network and its content.
- Authenticated ingest APIs for station measurements and webcam image uploads.

## Main Features

- Public monitoring UI for installations, weather summaries, charts, and webcam history.
- Back office for installations, stations, sensors, webcams, measurement types, faults, users, and blog pages.
- Station ingest API with single and bulk measurement submission.
- Webcam ingest API with image upload, WebP conversion, storage, and duplicate detection.
- Object-storage backed media handling for installation photos, webcam shots, and blog content files.

## `/ingest`

`/ingest` is a separate Go service, not part of the Phoenix runtime itself. It is used when you want to poll supported weather station or webcam sources and forward that data to this application's ingest APIs.

Start with `/ingest/README.md` for its configuration and runtime details.

## Developer Start

1. Start Postgres if you want to use the provided Docker service: `docker compose up db`
2. Check `config/dev.exs` before booting locally. The current dev database config points to a specific host and port, so you may need to change it for your machine.
3. Install dependencies and set up the app: `mix setup`
4. Start the server: `mix phx.server`
5. Run tests when needed: `mix test`
6. Before finishing changes, run: `mix precommit`

If you need media uploads and public media URLs in development, also review the storage-related environment variables used in `config/dev.exs` and `config/runtime.exs`.

## Application deployment
Application deployment happens via Docker Compose, check `docker-compose.prod.yml` and `.env.prod.example` for further information.   
API interface documentation can be found in the `docs` directory.
