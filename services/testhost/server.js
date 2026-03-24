#!/usr/bin/env node
// services/testhost/server.js — Lightweight file upload server for TRACE evidence
//
// No dependencies — Node.js built-ins only.
//
// Environment variables:
//   TESTHOST_PORT       — Listen port (default: 9090)
//   TESTHOST_UPLOAD_DIR — Where uploads are stored (default: ./uploads)
//   TESTHOST_MAX_SIZE   — Max upload size in bytes (default: 52428800 = 50MB)
//   TESTHOST_AUTH_TOKEN  — Optional auth token; if set, all requests must include
//                          Authorization: Bearer <token>

"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
const url = require("url");
const crypto = require("crypto");

const PORT = parseInt(process.env.TESTHOST_PORT || "9090", 10);
const UPLOAD_DIR = path.resolve(process.env.TESTHOST_UPLOAD_DIR || path.join(__dirname, "uploads"));
const MAX_SIZE = parseInt(process.env.TESTHOST_MAX_SIZE || String(50 * 1024 * 1024), 10);
const AUTH_TOKEN = process.env.TESTHOST_AUTH_TOKEN || "";

// Ensure upload directory exists
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

// MIME types for serving files
const MIME_TYPES = {
  ".html": "text/html",
  ".css": "text/css",
  ".js": "application/javascript",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
  ".pdf": "application/pdf",
  ".txt": "text/plain",
  ".log": "text/plain",
  ".md": "text/plain",
};

function getMime(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return MIME_TYPES[ext] || "application/octet-stream";
}

// Security: resolve and verify a path is inside UPLOAD_DIR
function safePath(requestedPath) {
  const resolved = path.resolve(UPLOAD_DIR, requestedPath);
  if (!resolved.startsWith(UPLOAD_DIR + path.sep) && resolved !== UPLOAD_DIR) {
    return null;
  }
  return resolved;
}

// Auth check — returns true if authorized
function checkAuth(req) {
  if (!AUTH_TOKEN) return true;
  const header = req.headers["authorization"] || "";
  return header === "Bearer " + AUTH_TOKEN;
}

// Today's date directory: YYYY-MM-DD
function todayDir() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

// Compact timestamp for filenames: YYYYMMDDTHHMMSSsss
function compactTimestamp() {
  const now = new Date();
  const y = now.getFullYear();
  const mo = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  const h = String(now.getHours()).padStart(2, "0");
  const mi = String(now.getMinutes()).padStart(2, "0");
  const s = String(now.getSeconds()).padStart(2, "0");
  const ms = String(now.getMilliseconds()).padStart(3, "0");
  return `${y}${mo}${d}T${h}${mi}${s}${ms}`;
}

// Sanitize a description for use in filenames
function sanitizeDesc(desc) {
  return desc
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .substring(0, 80);
}

// Deduplicate filename: if exists, add -1, -2, etc.
function deduplicatePath(filePath) {
  if (!fs.existsSync(filePath)) return filePath;
  const dir = path.dirname(filePath);
  const ext = path.extname(filePath);
  const base = path.basename(filePath, ext);
  let i = 1;
  while (true) {
    const candidate = path.join(dir, `${base}-${i}${ext}`);
    if (!fs.existsSync(candidate)) return candidate;
    i++;
    if (i > 9999) {
      // Safety valve
      return path.join(dir, `${base}-${crypto.randomBytes(4).toString("hex")}${ext}`);
    }
  }
}

// Parse multipart form data (minimal parser for file uploads)
function parseMultipart(buffer, boundary) {
  const parts = [];
  const boundaryBuf = Buffer.from("--" + boundary);
  const endBuf = Buffer.from("--" + boundary + "--");

  let pos = 0;
  // Find first boundary
  pos = bufferIndexOf(buffer, boundaryBuf, pos);
  if (pos === -1) return parts;
  pos += boundaryBuf.length + 2; // skip boundary + CRLF

  while (pos < buffer.length) {
    // Check for end boundary
    if (bufferIndexOf(buffer, endBuf, pos - boundaryBuf.length - 2) !== -1 &&
        pos >= buffer.length - 4) break;

    // Parse headers
    const headerEnd = bufferIndexOf(buffer, Buffer.from("\r\n\r\n"), pos);
    if (headerEnd === -1) break;
    const headerStr = buffer.slice(pos, headerEnd).toString("utf-8");
    pos = headerEnd + 4;

    // Parse header fields
    const headers = {};
    for (const line of headerStr.split("\r\n")) {
      const colonIdx = line.indexOf(":");
      if (colonIdx > 0) {
        headers[line.slice(0, colonIdx).trim().toLowerCase()] = line.slice(colonIdx + 1).trim();
      }
    }

    // Find next boundary
    const nextBoundary = bufferIndexOf(buffer, boundaryBuf, pos);
    if (nextBoundary === -1) break;

    // Content is between pos and nextBoundary - 2 (strip trailing CRLF)
    const content = buffer.slice(pos, nextBoundary - 2);
    pos = nextBoundary + boundaryBuf.length;

    // Skip CRLF or -- after boundary
    if (pos < buffer.length && buffer[pos] === 0x2d && buffer[pos + 1] === 0x2d) {
      // End boundary
      parts.push({ headers, content });
      break;
    }
    pos += 2; // skip CRLF

    // Extract filename and field name from Content-Disposition
    const disposition = headers["content-disposition"] || "";
    const nameMatch = disposition.match(/\bname="([^"]+)"/);
    const filenameMatch = disposition.match(/\bfilename="([^"]+)"/);

    parts.push({
      headers,
      content,
      fieldName: nameMatch ? nameMatch[1] : null,
      filename: filenameMatch ? filenameMatch[1] : null,
    });
  }

  return parts;
}

function bufferIndexOf(buf, search, fromIndex) {
  fromIndex = fromIndex || 0;
  for (let i = fromIndex; i <= buf.length - search.length; i++) {
    let found = true;
    for (let j = 0; j < search.length; j++) {
      if (buf[i + j] !== search[j]) {
        found = false;
        break;
      }
    }
    if (found) return i;
  }
  return -1;
}

// Send JSON response
function sendJSON(res, statusCode, data) {
  const body = JSON.stringify(data);
  res.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

// Send HTML response
function sendHTML(res, statusCode, html) {
  res.writeHead(statusCode, {
    "Content-Type": "text/html; charset=utf-8",
    "Content-Length": Buffer.byteLength(html),
  });
  res.end(html);
}

// Browse UI: list files in a directory
function renderBrowse(dirPath, urlPath) {
  const relativeTo = path.relative(UPLOAD_DIR, dirPath);
  const breadcrumb = relativeTo ? `uploads/${relativeTo}` : "uploads";

  let entries;
  try {
    entries = fs.readdirSync(dirPath, { withFileTypes: true });
  } catch {
    return null;
  }

  entries.sort((a, b) => {
    // Directories first, then by name descending (newest first)
    if (a.isDirectory() && !b.isDirectory()) return -1;
    if (!a.isDirectory() && b.isDirectory()) return 1;
    return b.name.localeCompare(a.name);
  });

  const rows = entries.map((entry) => {
    const entryPath = path.join(dirPath, entry.name);
    const href = urlPath.endsWith("/") ? urlPath + entry.name : urlPath + "/" + entry.name;
    const icon = entry.isDirectory() ? "&#128193;" : "&#128196;";
    let size = "";
    if (!entry.isDirectory()) {
      try {
        const stat = fs.statSync(entryPath);
        size = formatSize(stat.size);
      } catch {
        size = "?";
      }
    }
    return `<tr><td>${icon} <a href="${escapeHtml(href)}">${escapeHtml(entry.name)}</a></td><td>${size}</td></tr>`;
  }).join("\n");

  const parentLink = relativeTo
    ? `<p><a href="${escapeHtml(path.dirname(urlPath) || "/browse")}">&#8593; Parent</a></p>`
    : "";

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>testhost: ${escapeHtml(breadcrumb)}</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 800px; margin: 2em auto; padding: 0 1em; }
  table { width: 100%; border-collapse: collapse; }
  th, td { text-align: left; padding: 0.4em 0.8em; border-bottom: 1px solid #ddd; }
  th { background: #f5f5f5; }
  a { color: #0366d6; text-decoration: none; }
  a:hover { text-decoration: underline; }
  h1 { font-size: 1.4em; }
</style>
</head>
<body>
<h1>${escapeHtml(breadcrumb)}</h1>
${parentLink}
<table>
<tr><th>Name</th><th>Size</th></tr>
${rows}
</table>
<hr>
<p><small>testhost file server</small></p>
</body>
</html>`;
}

function formatSize(bytes) {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}

function escapeHtml(str) {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// Request handler
const server = http.createServer((req, res) => {
  if (!checkAuth(req)) {
    sendJSON(res, 401, { error: "Unauthorized" });
    return;
  }

  const parsed = url.parse(req.url, true);
  const pathname = decodeURIComponent(parsed.pathname);

  // POST /upload
  if (req.method === "POST" && pathname === "/upload") {
    handleUpload(req, res, parsed.query);
    return;
  }

  // GET /file/{path}
  if (req.method === "GET" && pathname.startsWith("/file/")) {
    handleFile(req, res, pathname.slice(6));
    return;
  }

  // GET /browse or /browse/{path}
  if (req.method === "GET" && (pathname === "/browse" || pathname.startsWith("/browse/"))) {
    handleBrowse(req, res, pathname);
    return;
  }

  // GET / — redirect to browse
  if (req.method === "GET" && pathname === "/") {
    res.writeHead(302, { Location: "/browse" });
    res.end();
    return;
  }

  sendJSON(res, 404, { error: "Not found" });
});

function handleUpload(req, res, query) {
  const contentType = req.headers["content-type"] || "";
  const contentLength = parseInt(req.headers["content-length"] || "0", 10);

  if (contentLength > MAX_SIZE) {
    sendJSON(res, 413, { error: `File too large. Max size: ${formatSize(MAX_SIZE)}` });
    return;
  }

  const chunks = [];
  let totalSize = 0;

  req.on("data", (chunk) => {
    totalSize += chunk.length;
    if (totalSize > MAX_SIZE) {
      sendJSON(res, 413, { error: `File too large. Max size: ${formatSize(MAX_SIZE)}` });
      req.destroy();
      return;
    }
    chunks.push(chunk);
  });

  req.on("end", () => {
    if (totalSize > MAX_SIZE) return;

    const body = Buffer.concat(chunks);
    const dateDir = todayDir();
    const datePath = path.join(UPLOAD_DIR, dateDir);
    fs.mkdirSync(datePath, { recursive: true });

    const description = sanitizeDesc(query.desc || query.description || "upload");
    const timestamp = compactTimestamp();

    // Multipart form data
    if (contentType.includes("multipart/form-data")) {
      const boundaryMatch = contentType.match(/boundary=([^\s;]+)/);
      if (!boundaryMatch) {
        sendJSON(res, 400, { error: "Missing multipart boundary" });
        return;
      }
      const parts = parseMultipart(body, boundaryMatch[1]);

      // Collect description from form fields
      let formDesc = description;
      const fileParts = [];
      for (const part of parts) {
        if (part.fieldName === "description" && !part.filename) {
          formDesc = sanitizeDesc(part.content.toString("utf-8"));
        } else if (part.filename) {
          fileParts.push(part);
        }
      }

      if (fileParts.length === 0) {
        sendJSON(res, 400, { error: "No file parts found" });
        return;
      }

      const results = [];
      for (let i = 0; i < fileParts.length; i++) {
        const part = fileParts[i];
        const ext = path.extname(part.filename || ".bin");
        const suffix = fileParts.length > 1 ? `-${i + 1}` : "";
        const baseName = `${timestamp}_${formDesc}${suffix}${ext}`;
        const filePath = deduplicatePath(path.join(datePath, baseName));

        fs.writeFileSync(filePath, part.content);

        const relPath = path.relative(UPLOAD_DIR, filePath);
        results.push({
          path: relPath,
          url: `/file/${relPath}`,
          size: part.content.length,
        });
      }

      sendJSON(res, 200, { files: results });
      return;
    }

    // Raw body upload (curl --data-binary, etc.)
    const ext = guessExtension(contentType);
    const baseName = `${timestamp}_${description}${ext}`;
    const filePath = deduplicatePath(path.join(datePath, baseName));

    fs.writeFileSync(filePath, body);

    const relPath = path.relative(UPLOAD_DIR, filePath);
    sendJSON(res, 200, {
      files: [{
        path: relPath,
        url: `/file/${relPath}`,
        size: body.length,
      }],
    });
  });

  req.on("error", () => {
    sendJSON(res, 500, { error: "Upload failed" });
  });
}

function guessExtension(contentType) {
  if (contentType.includes("image/png")) return ".png";
  if (contentType.includes("image/jpeg")) return ".jpg";
  if (contentType.includes("image/gif")) return ".gif";
  if (contentType.includes("image/webp")) return ".webp";
  if (contentType.includes("application/pdf")) return ".pdf";
  if (contentType.includes("text/plain")) return ".txt";
  if (contentType.includes("application/json")) return ".json";
  return ".bin";
}

function handleFile(req, res, filePath) {
  const resolved = safePath(filePath);
  if (!resolved) {
    sendJSON(res, 403, { error: "Forbidden" });
    return;
  }

  if (!fs.existsSync(resolved)) {
    sendJSON(res, 404, { error: "File not found" });
    return;
  }

  const stat = fs.statSync(resolved);
  if (stat.isDirectory()) {
    sendJSON(res, 400, { error: "Path is a directory. Use /browse/ instead." });
    return;
  }

  const mime = getMime(resolved);
  res.writeHead(200, {
    "Content-Type": mime,
    "Content-Length": stat.size,
  });
  fs.createReadStream(resolved).pipe(res);
}

function handleBrowse(req, res, pathname) {
  const subPath = pathname === "/browse" ? "" : pathname.slice(8); // strip "/browse/"
  const resolved = subPath ? safePath(subPath) : UPLOAD_DIR;

  if (!resolved) {
    sendHTML(res, 403, "<h1>Forbidden</h1>");
    return;
  }

  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isDirectory()) {
    sendHTML(res, 404, "<h1>Directory not found</h1>");
    return;
  }

  const html = renderBrowse(resolved, pathname);
  if (html === null) {
    sendHTML(res, 500, "<h1>Failed to read directory</h1>");
    return;
  }
  sendHTML(res, 200, html);
}

server.listen(PORT, () => {
  console.log(`testhost listening on http://localhost:${PORT}`);
  console.log(`  Upload dir: ${UPLOAD_DIR}`);
  console.log(`  Max size:   ${formatSize(MAX_SIZE)}`);
  console.log(`  Auth:       ${AUTH_TOKEN ? "enabled" : "disabled"}`);
  console.log(`  Browse:     http://localhost:${PORT}/browse`);
});
