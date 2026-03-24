# testhost — File Upload Server for TRACE Evidence

Lightweight file upload and screenshot server for devloop. No npm dependencies — Node.js built-ins only.

## Quick start

```bash
services/testhost/start.sh
```

Server runs at http://localhost:9090 by default.

## Configuration

All via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `TESTHOST_PORT` | 9090 | Listen port |
| `TESTHOST_UPLOAD_DIR` | `services/testhost/uploads` | Upload storage directory |
| `TESTHOST_MAX_SIZE` | 52428800 (50MB) | Max upload size in bytes |
| `TESTHOST_AUTH_TOKEN` | (none) | If set, requires `Authorization: Bearer <token>` on all requests |

## API

### POST /upload

Upload one or more files.

**Query parameters:**
- `desc` or `description` — description used in the filename (default: "upload")

**Multipart form upload:**
```bash
curl -F "file=@screenshot.png" -F "description=login-bug" http://localhost:9090/upload
```

**Raw body upload:**
```bash
curl -X POST --data-binary @output.log -H "Content-Type: text/plain" \
  "http://localhost:9090/upload?desc=build-failure"
```

**Multiple files:**
```bash
curl -F "file1=@before.png" -F "file2=@after.png" -F "description=visual-diff" \
  http://localhost:9090/upload
```

Multiple files get `-1`, `-2` suffixes automatically.

**Response:**
```json
{
  "files": [
    {
      "path": "2026-03-24/20260324T153012345_login-bug.png",
      "url": "/file/2026-03-24/20260324T153012345_login-bug.png",
      "size": 84521
    }
  ]
}
```

### GET /file/{path}

Serve an uploaded file.

```bash
curl http://localhost:9090/file/2026-03-24/20260324T153012345_login-bug.png
```

### GET /browse

Browse uploaded files in a simple HTML UI. Supports navigating into date directories.

## TRACE integration

Attach a testhost file to a TRACE:

```bash
scripts/trace-attach.sh .traces/trace-issue-42/ http://localhost:9090/file/2026-03-24/screenshot.png
```

This downloads the file into `<trace-dir>/artifacts/`.

## Security

- File paths are validated to prevent directory traversal
- Auth token checked on every request when `TESTHOST_AUTH_TOKEN` is set
- No secrets stored in code or config files
