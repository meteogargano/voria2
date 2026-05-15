# Webcam Ingest API

> **Status**: Phase 8 (COMPLETE)
> Real-time image ingestion with WebP conversion, R2 storage, and deduplication

## Overview

The Webcam Ingest API allows webcam owners to upload images for their webcams. Images are converted to WebP format, stored in R2 (via S3-compatible API), and a database record is created for archival and historical queries.

**Key features:**
- Image format auto-conversion to WebP
- Hash-based deduplication (same image content → same stored record)
- S3/R2 storage integration with configurable bucket
- File size validation (default 5 MB, configurable via env)
- Broadcast cache invalidation for LiveView updates

---

## Endpoints

### Verify Webcam

**Method:** `POST`
**Path:** `/api/v1/webcam/ingest/verify`
**Content-Type:** `application/json`

#### Authentication

Same two methods as upload:

1. **X-Api-Key Header** (preferred)
    ```
    X-Api-Key: wk_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
    ```

2. **Bearer Token** (Authorization header)
    ```
    Authorization: Bearer wk_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
    ```

Either method will authenticate the request. Missing or invalid keys return **401**.

#### Request Body

None (empty JSON object `{}` or no body).

#### Response – Success (200 OK)

```json
{
  "ok": true,
  "webcam_id": "550e8400-e29b-41d4-a716-446655440000",
  "webcam_name": "My Webcam"
}
```

#### Response – Unauthorized (401)

**Missing or invalid API key:**
```json
{
  "error": "missing_api_key"
}
```

```json
{
  "error": "invalid_api_key"
}
```

### Upload Webcam Image

**Method:** `POST`
**Path:** `/api/v1/webcam/ingest`
**Content-Type:** `multipart/form-data`

#### Authentication

Two methods supported (priority order):

1. **X-Api-Key Header** (preferred)
   ```
   X-Api-Key: wk_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
   ```

2. **Bearer Token** (Authorization header)
   ```
   Authorization: Bearer wk_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
   ```

Either method will authenticate the request. Missing or invalid keys return **401**.

#### Request Body

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `image` | File | Yes | Binary image file (JPEG, PNG, WebP, etc.) |

#### Query Parameters

None.

#### Response – Success (201 Created)

**When image is new and successfully processed:**

```json
{
  "ok": true,
  "shot_id": "550e8400-e29b-41d4-a716-446655440000",
  "s3_key": "webcams/550e8400-e29b-41d4-a716-446655440000/2026-03-18/12345678.webp"
}
```

**When image is a duplicate (same content hash):**

```json
{
  "ok": true,
  "duplicate": true,
  "shot_id": "550e8400-e29b-41d4-a716-446655440000",
  "s3_key": "webcams/550e8400-e29b-41d4-a716-446655440000/2026-03-18/12345678.webp"
}
```

#### Response – Error (422 Unprocessable Entity)

**Invalid image format:**
```json
{
  "ok": false,
  "error": "invalid image: ..."
}
```

**Image exceeds size limit:**
```json
{
  "ok": false,
  "error": "image exceeds maximum allowed size"
}
```

**Other errors (auth, upload, etc.):**
```json
{
  "ok": false,
  "error": "..."
}
```

#### Response – Unauthorized (401)

**Missing or invalid API key:**
```json
{
  "error": "missing_api_key"
}
```

```json
{
  "error": "invalid_api_key"
}
```

---

## Webcam API Key Management

Webcam API keys are generated per-webcam by the owner or admin.

### Generate a Webcam API Key

**Via Ash code interface:**
```elixir
{:ok, api_key} = Voria2.Network.generate_webcam_api_key(webcam_id, actor: user)
# Returns: %Voria2.Network.WebcamApiKey{
#   key: "wk_...",
#   webcam_id: ...,
#   ...
# }
```

**Key format:** `wk_` prefixed, 32 random bytes (hex-encoded), totaling 67 characters.

### Revoke a Webcam API Key

```elixir
{:ok, _} = Voria2.Network.revoke_webcam_api_key(api_key_record, actor: user)
```

---

## Data Storage

### WebcamShot Record

Each successfully processed upload creates a `WebcamShot` record:

| Field | Type | Details |
|-------|------|---------|
| `id` | UUID | Primary key |
| `webcam_id` | UUID | Reference to the webcam |
| `captured_at` | DateTime | When the shot was captured (set to upload time) |
| `s3_key` | String | Path in R2, e.g. `webcams/{webcam_id}/{date}/{unique_id}.webp` |
| `s3_bucket` | String | Bucket name (default: `voria2-media`) |
| `original_hash` | String | SHA256 of the original uploaded binary (lower hex) |
| `width` | Integer | WebP image width in pixels |
| `height` | Integer | WebP image height in pixels |
| `file_size_bytes` | Integer | Size of the WebP file in bytes |

### Deduplication Logic

If two uploads have the same binary content (SHA256 hash), the second upload:
- Returns `{"ok": true, "duplicate": true, ...}`
- **Does NOT** upload to R2 again
- **Does NOT** create a new shot record
- Returns the original shot's ID and S3 key

This prevents wasted storage and redundant uploads.

---

## Configuration

### Environment Variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `STORAGE_ENDPOINT` | Yes (if uploading) | None | S3-compatible endpoint (e.g., `https://s3.example.com:443`) |
| `STORAGE_ACCESS_KEY_ID` | Yes (if uploading) | None | S3 access key ID |
| `STORAGE_SECRET_ACCESS_KEY` | Yes (if uploading) | None | S3 secret access key |
| `STORAGE_BUCKET` | No | `voria2-media` | R2 bucket name |
| `STORAGE_REGION` | No | `auto` | S3 region (R2 uses `auto`) |
| `MAX_WEBCAM_UPLOAD_MB` | No | `5` | Max upload size in MB |

### Code Configuration

| Key | Type | Default | Purpose |
|---|---|---|---|
| `:storage_adapter` | Atom | `Voria2.Storage.R2` | Storage backend module |
| `:storage_bucket` | String | `voria2-media` | Bucket for uploads |
| `:max_webcam_upload_bytes` | Integer | `5242880` (5 MB) | Max upload size in bytes |

---

## Architecture

### Processing Pipeline

```
HTTP Upload (multipart/form-data)
    ↓
WebcamIngestAuth plug (validate API key)
    ↓
WebcamIngestController:create
    ↓
File size check
    ↓
Image.from_binary/1 (parse image)
    ↓
Image.write/3 (convert to WebP)
    ↓
Voria2.Storage.upload/3 (upload to R2)
    ↓
Voria2.Network.record_webcam_shot/1 (save metadata)
    ↓
Voria2.Cache.broadcast_webcam_shot/1 (notify LiveView)
    ↓
HTTP 201 with shot_id and s3_key
```

### Key Modules

- **`Voria2Web.Plugs.WebcamIngestAuth`** — Extracts and validates API key from header
- **`Voria2Web.WebcamIngestController`** — Handles upload, size checking, error formatting
- **`Voria2.WebcamIngest`** — Core pipeline: hash, dedup, convert, upload, record
- **`Voria2.Storage`** — S3/R2 adapter delegation
- **`Voria2.Cache`** — Redis cache for key→webcam lookups and PubSub broadcast

---

## Examples

### cURL

```bash
# Verify webcam identity
curl -X POST \
  -H "X-Api-Key: wk_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" \
  http://localhost:4000/api/v1/webcam/ingest/verify

# Response (200):
# {"ok": true, "webcam_id": "550e8400-...", "webcam_name": "My Webcam"}

# Upload an image
curl -X POST \
  -H "X-Api-Key: wk_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" \
  -F "image=@path/to/image.jpg" \
  http://localhost:4000/api/v1/webcam/ingest

# Response (201):
# {"ok": true, "shot_id": "550e8400-...", "s3_key": "webcams/550e8400-..."}
```

### Python

```python
import requests

api_key = "wk_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Verify webcam identity
verify_url = "http://localhost:4000/api/v1/webcam/ingest/verify"
headers = {"X-Api-Key": api_key}
response = requests.post(verify_url, headers=headers)
print(response.json())
# {'ok': True, 'webcam_id': '550e8400-...', 'webcam_name': 'My Webcam'}

# Upload an image
url = "http://localhost:4000/api/v1/webcam/ingest"

with open("image.jpg", "rb") as f:
    files = {"image": f}
    headers = {"X-Api-Key": api_key}
    response = requests.post(url, files=files, headers=headers)

print(response.json())
# {'ok': True, 'shot_id': '550e8400-...', 's3_key': 'webcams/550e8400-...'}
```

### JavaScript/Node.js

```javascript
const FormData = require("form-data");
const fs = require("fs");
const axios = require("axios");

const apiKey = "wk_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";

// Verify webcam identity
const verifyUrl = "http://localhost:4000/api/v1/webcam/ingest/verify";
axios.post(verifyUrl, {}, {
  headers: { "X-Api-Key": apiKey }
})
  .then(res => console.log(res.data))
  .catch(err => console.error(err.response.data));
// { ok: true, webcam_id: '550e8400-...', webcam_name: 'My Webcam' }

// Upload an image
const url = "http://localhost:4000/api/v1/webcam/ingest";

const form = new FormData();
form.append("image", fs.createReadStream("image.jpg"));

axios.post(url, form, {
  headers: {
    ...form.getHeaders(),
    "X-Api-Key": apiKey,
  },
})
  .then(res => console.log(res.data))
  .catch(err => console.error(err.response.data));
```

---

## Testing

### Unit Tests

The API is covered by tests in `test/voria2_web/controllers/webcam_ingest_controller_test.exs`:

- Verify endpoint (X-Api-Key and Bearer authentication)
- Auth validation (missing, invalid, empty key)
- Successful upload (new image)
- Duplicate detection
- Size limit enforcement
- Image format conversion
- WebP dimension and size extraction
- Error formatting

Run:
```bash
mix test test/voria2_web/controllers/webcam_ingest_controller_test.exs
```

### Manual Testing

Generate an API key for a webcam:
```elixir
{:ok, key} = Voria2.Network.generate_webcam_api_key(webcam_id, actor: admin)
```

Then use any of the examples above with that key.

---

## Troubleshooting

### 401 Unauthorized

- Check API key is prefixed with `wk_`
- Verify header format: `X-Api-Key: wk_...` (case-insensitive)
- Ensure the webcam still exists and is active
- Check cache hasn't staled (clears every 5 minutes)

### 422 Image Exceeds Maximum Size

- Default limit: 5 MB
- Configure with `MAX_WEBCAM_UPLOAD_MB` env var
- Example: `MAX_WEBCAM_UPLOAD_MB=10` allows 10 MB uploads

### 422 Invalid Image

- Ensure file is a valid image format (JPEG, PNG, WebP, etc.)
- Check file isn't corrupted
- Verify `Image` library supports the format (most common formats work)

### Image Not Appearing in R2

- Verify `STORAGE_ENDPOINT`, access key, and secret are correct
- Check bucket name matches
- Ensure credentials have write permissions to the bucket

---

## Security Considerations

- **API keys are sensitive** — treat like passwords, use environment variables
- **Deduplication uses content hash** — identical images (rare uploads of same content) safely deduplicate
- **S3/R2 credentials in env** — keep in secrets manager, never commit to repo
- **File size limit** — prevents DoS via large uploads
- **Image validation** — `Image` library rejects malformed files early

---

## Future Enhancements

- Per-webcam rate limiting
- Image processing pipeline (watermarking, blanking)
- Webhook notifications on successful upload
- Bulk upload endpoint
- Timelapse generation via FFmpeg
