# Voria2 Station Ingest API

The Ingest API allows weather stations to submit measurement data in real-time. All requests must include a valid API key via the `X-Api-Key` header.

## Base URL

```
POST https://api.voria2.io/api/v1/ingest/...
```

## Authentication

Include your station's API key in every request:

```
X-Api-Key: vsk_xxxxxxxxxxxxxxxxxxxx
```

API keys are issued per station and begin with `vsk_`. If you don't have a key, contact your network administrator.

---

## Endpoint: Verify API Key

Quickly verify that your API key is valid and retrieve associated station information.

```
POST /api/v1/ingest/verify
```

### Request

```bash
curl -X POST https://api.voria2.io/api/v1/ingest/verify \
  -H "X-Api-Key: vsk_xxxxxxxxxxxxxxxxxxxx"
```

### Success Response (200 OK)

```json
{
  "ok": true,
  "station_id": "550e8400-e29b-41d4-a716-446655440000",
  "station_name": "Weather Station Alpha"
}
```

### Error Responses

**Missing API key (401 Unauthorized):**
```json
{
  "error": "missing_api_key"
}
```

**Invalid API key (401 Unauthorized):**
```json
{
  "error": "invalid_api_key"
}
```

---

## Endpoint: Submit Single Measurement

Submit one measurement at a time.

```
POST /api/v1/ingest
```

### Request Format

```json
{
  "sensor_slug": "string",
  "measurement_type": "string",
  "value": number,
  "measured_at": "ISO 8601 timestamp (optional)",
  "...": "type-specific fields"
}
```

- **sensor_slug**: Identifier for the sensor (required)
- **measurement_type**: Type of measurement—one of: `temperature`, `humidity`, `pressure`, `wind`, `rain`, `custom` (required)
- **measured_at**: ISO 8601 timestamp (defaults to current time if omitted, UTC recommended)
- **Type-specific fields**: See measurement types below

### Success Response (201 Created)

```json
{
  "ok": true
}
```

### Error Response (422 Unprocessable Entity)

```json
{
  "ok": false,
  "error": "sensor_slug: unknown sensor slug"
}
```

---

## Measurement Types

### Temperature

```json
{
  "sensor_slug": "outdoor_temp",
  "measurement_type": "temperature",
  "value": 22.5
}
```

- **value**: Temperature in degrees Celsius (required, number)

---

### Humidity

```json
{
  "sensor_slug": "outdoor_humidity",
  "measurement_type": "humidity",
  "value": 65.0
}
```

- **value**: Relative humidity as percentage 0–100 (required, number)

---

### Pressure

```json
{
  "sensor_slug": "barometer",
  "measurement_type": "pressure",
  "value": 1013.25
}
```

- **value**: Atmospheric pressure in hPa/mbar (required, number)

---

### Wind

```json
{
  "sensor_slug": "anemometer",
  "measurement_type": "wind",
  "u": -2.5,
  "v": 3.8,
  "gust": 8.2
}
```

- **u**: Eastward wind component in m/s (required, number)
- **v**: Northward wind component in m/s (required, number)
- **gust**: Peak gust speed in m/s (required, number)

Wind speed is computed internally from u and v components.

---

### Rain

Submit rain as either **interval** (amount during time window) or **cumulative** (running total). Do not submit both in the same request.

**Interval mode:**
```json
{
  "sensor_slug": "rain_gauge",
  "measurement_type": "rain",
  "mode": "interval",
  "value": 5.2
}
```

**Cumulative mode:**
```json
{
  "sensor_slug": "rain_gauge",
  "measurement_type": "rain",
  "mode": "cumulative",
  "value": 125.3
}
```

- **mode**: Either `interval` or `cumulative` (required, string)
- **value**: Rainfall in mm (required, non-negative number)

---

### Custom Measurements

For non-standard sensors, use the custom measurement type with a label.

```json
{
  "sensor_slug": "soil_moisture",
  "measurement_type": "custom",
  "label": "soil_moisture",
  "value": 45.2
}
```

- **label**: Measurement category or sensor name (required, string)
- **value**: Numeric value (either `value` or `raw` is required)

Alternatively, submit raw string data:
```json
{
  "sensor_slug": "soil_sensor",
  "measurement_type": "custom",
  "label": "soil_status",
  "raw": "dry"
}
```

---

## Endpoint: Bulk Submit

Submit multiple measurements in one request for efficiency.

```
POST /api/v1/ingest/bulk
```

### Request Format

Submit a JSON array of measurement objects. The body must be sent as raw JSON array, not wrapped in an object.

```json
[
  {
    "sensor_slug": "outdoor_temp",
    "measurement_type": "temperature",
    "value": 22.5
  },
  {
    "sensor_slug": "outdoor_humidity",
    "measurement_type": "humidity",
    "value": 65.0
  }
]
```

### Success Response (200 OK)

```json
{
  "ok": true,
  "count": 2,
  "results": [
    {
      "index": 0,
      "ok": true
    },
    {
      "index": 1,
      "ok": true
    }
  ]
}
```

### Mixed Success/Error Response

Bulk requests process all items; successful items don't block failed ones. The `count` field shows how many succeeded.

```json
{
  "ok": true,
  "count": 1,
  "results": [
    {
      "index": 0,
      "ok": true
    },
    {
      "index": 1,
      "ok": false,
      "error": "sensor_slug: unknown sensor slug"
    }
  ]
}
```

---

## Error Handling

| Status | Error | Cause |
|--------|-------|-------|
| 401 | `missing_api_key` | No `X-Api-Key` header provided |
| 401 | `invalid_api_key` | API key does not exist or is revoked |
| 422 | `missing required fields: ...` | Required field absent |
| 422 | `sensor_slug: unknown sensor slug` | Sensor not found on this station |
| 422 | `{field}: {reason}` | Field validation failed (e.g., "value: must be a number") |

---

## Timestamps

The `measured_at` field is optional; if omitted, the server records the current time.

**Recommended format (ISO 8601 UTC):**
```
2026-03-18T14:30:45Z
```

**Other accepted formats:**
- `2026-03-18T14:30:45+00:00` (explicit UTC offset)
- `2026-03-18T14:30:45` (treated as UTC)

Future and past timestamps are accepted. Use accurate timestamps whenever possible to avoid skewing time-series analytics.

---

## Best Practices

1. **Use bulk submit** for multiple readings to reduce network overhead and improve reliability.
2. **Include timestamps** from your sensor clock rather than relying on server time.
3. **Monitor HTTP status codes**—bulk requests return 200 even when some items fail; check the `results` array.
4. **Validate sensor slugs** against your station's sensor list before scripting.
5. **Retry with exponential backoff** on 5xx errors; don't retry 401/422 without fixing the request.
6. **Cache the verify endpoint result** to avoid repeating key validation in rapid-fire scripts.

---

## Examples

### Python

```python
import requests
import json
from datetime import datetime

API_KEY = "vsk_xxxxxxxxxxxxxxxxxxxx"
BASE_URL = "https://api.voria2.io/api/v1/ingest"

headers = {"X-Api-Key": API_KEY}

# Verify key
resp = requests.post(f"{BASE_URL}/verify", headers=headers)
print(resp.json())

# Single measurement
payload = {
    "sensor_slug": "outdoor_temp",
    "measurement_type": "temperature",
    "value": 22.5,
    "measured_at": datetime.utcnow().isoformat() + "Z"
}
resp = requests.post(f"{BASE_URL}", json=payload, headers=headers)
print(resp.json())

# Bulk submit
payloads = [
    {"sensor_slug": "outdoor_temp", "measurement_type": "temperature", "value": 22.5},
    {"sensor_slug": "outdoor_humidity", "measurement_type": "humidity", "value": 65.0}
]
resp = requests.post(f"{BASE_URL}/bulk", json=payloads, headers=headers)
print(resp.json())
```

### cURL

```bash
API_KEY="vsk_xxxxxxxxxxxxxxxxxxxx"

# Verify key
curl -X POST https://api.voria2.io/api/v1/ingest/verify \
  -H "X-Api-Key: $API_KEY"

# Single measurement
curl -X POST https://api.voria2.io/api/v1/ingest \
  -H "X-Api-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "sensor_slug": "outdoor_temp",
    "measurement_type": "temperature",
    "value": 22.5
  }'

# Bulk submit
curl -X POST https://api.voria2.io/api/v1/ingest/bulk \
  -H "X-Api-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '[
    {"sensor_slug": "outdoor_temp", "measurement_type": "temperature", "value": 22.5},
    {"sensor_slug": "outdoor_humidity", "measurement_type": "humidity", "value": 65.0}
  ]'
```

---

## Support

For issues or questions, contact your network administrator or the Voria2 support team.
