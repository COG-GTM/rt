# External Storage Service

A standalone HTTP service for managing content-addressable blob storage, extracted from RT's ExternalStorage subsystem. Supports multiple storage backends: Disk, Amazon S3, and Dropbox.

## Quick Start

```bash
# Install dependencies
cpanm --installdeps .

# Configure (copy and edit the example config)
cp etc/config.yml.example etc/config.yml

# Or use environment variables
export STORAGE_TYPE=Disk
export STORAGE_PATH=/var/attachments

# Start the server
perl bin/external-storage-server
```

The server listens on `http://*:8080` by default. Override with `ESS_LISTEN` env var or `listen` in config.

## HTTP API

### Health Check

```
GET /health
```

Returns backend status.

```json
{"status": "healthy", "backend": "Disk"}
```

### Store a Blob (auto-compute SHA-256)

```
POST /blob
Content-Type: application/octet-stream

<raw bytes>
```

Returns `201 Created` with the computed SHA-256:

```json
{"sha256": "abc123..."}
```

### Store a Blob (explicit SHA-256)

```
PUT /blob/:sha256
Content-Type: application/octet-stream

<raw bytes>
```

The server verifies the content matches the provided SHA-256. Returns `400` on mismatch.

### Retrieve a Blob

```
GET /blob/:sha256
```

Returns the raw blob content, or `404` if not found.

### Delete a Blob

```
DELETE /blob/:sha256
```

Returns:

```json
{"sha256": "abc123...", "deleted": true}
```

### Get Download URL

```
GET /download-url/:sha256
```

Returns a direct download URL if the backend supports it (e.g., S3). Disk and Dropbox return `null`.

```json
{"sha256": "abc123...", "url": "https://bucket.s3.amazonaws.com/abc123..."}
```

## Configuration

Configuration can be provided via a YAML config file, environment variables, or both (env vars take precedence).

### Config File

Default location: `etc/config.yml` (override with `ESS_CONFIG_FILE` env var).

See `etc/config.yml.example` for all options.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `STORAGE_TYPE` | Backend type: `Disk`, `AmazonS3`, or `Dropbox` |
| `ESS_LISTEN` | Listen address (default: `http://*:8080`) |
| `ESS_CONFIG_FILE` | Path to config file |
| **Disk** | |
| `STORAGE_PATH` | Directory path for file storage |
| **AmazonS3** | |
| `S3_ACCESS_KEY_ID` | AWS access key |
| `S3_SECRET_ACCESS_KEY` | AWS secret key |
| `S3_BUCKET` | S3 bucket name |
| `S3_HOST` | S3 endpoint (optional) |
| `S3_REGION` | AWS region (optional) |
| **Dropbox** | |
| `DROPBOX_APP_KEY` | Dropbox app key |
| `DROPBOX_APP_SECRET` | Dropbox app secret |
| `DROPBOX_REFRESH_TOKEN` | Dropbox refresh token |

## Storage Backends

### Disk

Stores blobs on the local filesystem in a fan-out directory structure (`$path/$first3/$next3/$rest`) to avoid large single directories.

### AmazonS3

Stores blobs in an Amazon S3 bucket. Supports optional `Content-Type` header on PUT for correct MIME type storage. The `GET /download-url/:sha256` endpoint returns a direct S3 URL.

### Dropbox

Stores blobs in Dropbox using the WebService::Dropbox module. Files are stored at `/$sha` path in Dropbox.

## Content-Addressable Storage

All blobs are stored using their SHA-256 hash as the key. This provides:

- **Deduplication**: Identical content is stored only once
- **Integrity verification**: Content can be verified against its hash
- **Idempotent writes**: Storing the same content twice is a no-op

## Running Tests

```bash
cd external-storage-service
prove -Ilib t/
```

## Dependencies

Core dependencies (see `cpanfile`):

- Mojolicious (>= 9.0)
- Role::Basic
- Digest::SHA
- JSON::PP
- YAML::Tiny

Backend-specific:

- Amazon::S3 (for S3 backend)
- WebService::Dropbox (for Dropbox backend)
