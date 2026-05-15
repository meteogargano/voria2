FROM golang:1.25.6-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/voria2ingest ./cmd

FROM alpine:3.22

RUN apk add --no-cache ca-certificates tzdata wget

WORKDIR /app

COPY --from=build /out/voria2ingest /app/voria2ingest

EXPOSE 8080 2121 30000-30010

ENTRYPOINT ["/app/voria2ingest"]
CMD ["/app/config.yaml"]
