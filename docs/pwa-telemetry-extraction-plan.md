# PWA Telemetry + Bug-Reporting Extraction Plan

Status: PROPOSAL (design doc, not committed as work). Review before slicing.
Author: planning agent. For: owner + scrapdaw agent.

## Why this exists (the mobissh insight)

MobiSSH's key operational win is that a bug report is **self-diagnosing**: every
report carries the recent, always-on, backward-looking history (telemetry rings +
screenshot + app state), so most fixes are one-shot instead of multi-build guessing
loops. Memory anchor `feedback_robust_inapp_telemetry`: "on-device telemetry turns
multi-build loops into one-shot fixes. Invest before blind fixes." Anchor
`feedback_screenshot_bug_reports`: the orchestrator checks `test-results/uploads/`
after every user message. Anchor `reference_repro_recording`: reports carry rings
(connect/gesture/lifecycle) plus optional frame bursts.

The mechanism is generic. The *rings' contents* (SSH connect events, terminal byte
traces) are not. This plan lifts the generic mechanism into devloop and draws a hard
line so no SSH/terminal concept comes along.

## 1. What the shared devloop module IS

A framework-agnostic web bug-reporting + telemetry package, proposed at
`devloop/services/web-feedback/` (sibling to the existing `services/testhost/`,
which already renders `test-results/uploads/` — see §Synergy). Three parts:

### (a) Client — `services/web-feedback/client/` (TS source, ES-module output)

Plain ES modules, zero framework assumptions, vendors `html2canvas`. Public API:

```
const feedback = createFeedback({
  endpoint: '/api/bug-report',          // configurable (seam)
  version:  () => metaVersion(),         // build-rev source (seam)
  screenshotTarget: () => document.getElementById('app'),  // seam
  captureState:     () => ({ view, ... }),                 // seam (app snapshot)
  getConsoleLog:    () => [...],          // seam OR use built-in console tap
  scrubbers: [ /password=\S+/gi, ... ],  // extensible secret patterns
});

const ring = feedback.ring('audio-engine', { maxAgeMs, maxEntries });  // named ring
ring.log('xrun', { bufferMs: 12 });

feedback.trigger();                       // button handler: shot + rings + state → scrub → POST
feedback.autoUpload({ endpoint: '/api/drop-telemetry', throttleMs, reason }); // passive
```

Sub-modules (each a straight generalization of a mobissh file):

- `rings.ts` — `createRing(name, opts)`. The connect-log/gesture-log pattern
  factored to ONE abstraction. mobissh's `connect-log.js` and `gesture-log.js` are
  byte-for-byte the same ring (localStorage-backed, 24h age cap + 5000-entry hard
  cap, prune-on-write, quota-exceeded → drop oldest half, `log/get/format/download/
  clear`; see `public/modules/connect-log.js:12-107` vs `gesture-log.js:16-117`).
  That duplication IS the evidence the abstraction should be shared.
- `capture.ts` — screenshot (html2canvas on a host-provided element; hide-overlay-
  first pattern generalized to an optional `beforeCapture`/`afterCapture` hook, from
  `bug-report.js:31-62`), console/log capture, `captureState()` snapshot, metadata
  (userAgent, url, version).
- `scrub.ts` — pattern-based secret scrubbing applied to logs + ring payloads before
  upload (NEW — see §4; mobissh's web side has no scrubber today).
- `report.ts` — assembles the payload and POSTs; returns the server's response
  (`{issueUrl}` / `{ok}`). From `bug-report.js:68-102`.
- `auto-upload.ts` — throttled, fire-and-forget, silent-on-failure passive uploads
  (drop/anomaly recovery). From `drop-telemetry.js` (localStorage throttle keys,
  5/10-min windows, mark-before-fetch to dedupe concurrent fires).

### (b) Server — `services/web-feedback/server/`

- `feedback-store.js` — generalized copy of mobissh `server/feedback-store.js`.
  Keep verbatim: `stampNow()` server-generated ISO filename prefix (this IS the path-
  injection sanitization — no user-controlled path component ever hits disk,
  `feedback-store.js:22-23,47-50`), `readBody(req, maxBytes)` with size cap +
  `TOO_LARGE` → 413, `sweepRetention(dir, days)` (default 0 = keep all),
  `handleFeedbackRequest(route, body, dir) → {status, body, sse}` dispatch. Generalize
  `saveBugReport` to write the GENERIC fields (screenshot, logs/comment, named-ring
  JSON sidecars, version/url/userAgent meta) and route any app-specific blobs through
  a host-extensible "extras" writer (see §3) instead of hard-coding byteTrace/
  scrollTrace/sentSgrTrace/grid/frames.
- `service/index.js` — standalone Node-http ingest service (no deps). Generalized copy
  of mobissh `server-feedback/index.js`: routes = FEEDBACK_ROUTES, `GET /healthz`
  (liveness + config), `PORT`/`HOST`/`UPLOADS_DIR`/`RETENTION_DAYS` env. This is the
  DEPLOY-shape precedent (#997): a dedicated feedback container.
- `docker/Dockerfile` — from mobissh `docker/feedback/Dockerfile`: build context = repo
  root, copies only `feedback-store.js` + service, bakes git hash for `/healthz`.

### (c) Freshness helper — `services/web-feedback/freshness/`

The "always-fresh test instance, never force-reload" piece:

- A documented `Cache-Control: no-store` static-response snippet (mobissh sets it on
  ALL static responses, `server/index.js:982`; scrapdaw already does, `scripts/
  serve.js:55`).
- A parameterized **network-first service-worker template** (from mobissh `public/
  sw.js:125-172`): try network, cache is offline fallback only; skip caching
  `no-store` responses (`sw.js:148-154`); `activate` purges every cache whose name
  isn't the current build-rev-derived `CACHE_NAME` (`sw.js:54-64`); `?reset=1` +
  `/clear` recovery route (`sw.js:136-143`, `server/index.js:900-916`).
- A **build-rev cache-name** convention: `CACHE_NAME = "<app>-" + buildRev`. scrapdaw
  already computes `buildRev` (git commit count) and injects `__BUILD_REV__`
  (`vite.config.ts:7-19`); the template consumes exactly that so the SW auto-purges on
  every build with no manual bump (scrapdaw's current `sw.js` uses a hand-bumped
  `scrapdaw-shell-v2`, `public/sw.js:6` — the template removes that footgun).

## 2. Host-app SEAMS (interface contract)

| Concern | devloop provides | Host app implements |
|---|---|---|
| Telemetry rings | `createRing(name, opts)`: storage, prune, caps, download/clear | WHICH rings exist + WHAT events they log (the producers) |
| Screenshot | html2canvas capture + before/after hooks | `screenshotTarget()` element; optional overlay-hide hook |
| App state | snapshot serialization into payload | `captureState()` returning a plain JSON object |
| Console log | optional console tap + formatter | OR feed `getConsoleLog()` from its own log buffer |
| Secret scrubbing | scrub engine + a default pattern set | additional `scrubbers` for its own data shapes |
| Upload | POST + throttle + fail-open | endpoint URL(s); when to call `trigger()`/`autoUpload()` |
| Build-rev / version | reads a supplied `version()` | the source (meta tag, `__BUILD_REV__`, etc.) |
| Freshness | no-store snippet + SW template + cache-name rule | wire the template with its app slug + build-rev; serve no-store |
| Ingest | feedback-store + standalone service + Dockerfile | pick deploy shape (§7); mount an uploads dir |
| Feedback UI trigger | none (intentionally) | the button/gesture + placement (mobissh: a debug FAB) |

Rule: the module owns **mechanism**; the host owns **content and placement**.

## 3. Generic vs app-specific (the hard line)

Portable (goes in the module):
- Screenshot (html2canvas), console capture, app-state snapshot.
- Generic **named rings** — `connect-log` and `gesture-log` are just two instances;
  the module ships the ring, not those names.
- Passive throttled auto-upload (drop/anomaly recovery shape).
- Upload/persist (server-stamped filenames, size caps, retention sweep, SSE broadcast
  hook) and freshness (no-store + network-first SW + build-rev cache name).
- Secret scrubbing.

App-specific (stays OUT; becomes host-registered rings or "extras", never built-ins):
- SSH/terminal payloads: `byteTrace`, `scrollTrace`, `sentSgrTrace`, `grid`, repro
  `frames`, paint-stats, control-mode traces (`feedback-store.js:194,265-306`).
- The event vocabularies: WS open/close, SSH ready, reconnect probes (connect-log);
  swipe/pinch/long-press (gesture-log). These are ring *contents*.
- The native-crash route is Android-APK-specific (`feedback-store.js:172-190`); keep
  it as an OPTIONAL route the host enables, not a core assumption.

Concretely: generalize `saveBugReport` so the terminal blobs become entries an app
registers via an `extras` map (`name → {payload, cap}`) written as `<stamp>-bug-report.
<name>.json`. mobissh then registers byteTrace/scrollTrace/etc as its own extras; the
shared code never mentions them.

## 4. Security

- **Secret scrubbing must live in the shared client** and run before every upload.
  GAP FOUND: mobissh's web `bug-report.js` does NO scrubbing — it trusts callers not
  to log secrets (`connect-log.js:10-11` comment only). The shared module must add a
  pattern-based `scrub.ts` applied to `logs`, `captureState()` output, and every ring
  payload, with a default set (password/passphrase/token/`Authorization:`/private-key
  headers) plus host-extensible `scrubbers`. Precedent to mirror: native
  `feedback_bundle.dart:scrubSecrets` (native-only today).
- **Screenshot residual risk (call out to owner):** pixels can't be pattern-scrubbed.
  A secret visible on screen rides along in the PNG. mobissh mitigates only by hiding
  the debug overlay (`bug-report.js:31-37`). Options for the module: (i) host-provided
  mask selectors blanked before capture, (ii) a confirm-preview step, (iii) leave it to
  the host. Recommend (i) as an optional seam; flag (ii) for owner.
- **Ingest posture:** 127.0.0.1 / tailnet-only by default. mobissh relies on the
  Tailscale network layer (no app-level auth) and a single proxied endpoint with
  fail-open local fallback (`server/index.js:253-287`). scrapdaw's preview binds
  `0.0.0.0` (`serve.js:14`) — its ingest needs an explicit decision (token or bind to
  loopback/tailnet). Open question §7.
- **Size caps (already present, keep):** 1MB crash body, 1MB gesture-log sidecar, 120
  frames, 8192 events/trace (`feedback-store.js:29-37`); `readBody` enforces the body
  cap and 413s (`feedback-store.js:57-83`). Server-generated filenames = no path
  injection.

## 5. scrapdaw adoption (Vite/TS PWA — the adopting app)

scrapdaw already has most of the freshness substrate; adoption is mostly wiring.

- **Freshness:** already serves `no-store` (`serve.js:55`) and computes `buildRev`
  (git commit count → `__BUILD_REV__`, `vite.config.ts:7-19`) with a visible `#build-
  rev` badge (`index.html:21`, `main.ts:27`). Swap `public/sw.js` (hand-bumped
  `scrapdaw-shell-v2`, network-first already) for the devloop template parameterized
  with `scrapdaw` + `__BUILD_REV__` so cache-name auto-purges per build.
- **Feedback trigger:** add a button (fits its topbar next to the build-rev badge);
  wire to `feedback.trigger()`. `screenshotTarget = () => document.body` (or its main
  app root). Vite's asset hashing already handles JS/CSS freshness.
- **Its own rings:** e.g. `audio-engine` (xruns, buffer under/overruns, MIDI device
  connect/disconnect, AudioContext state changes) and `ui-state` (view switches,
  transport events). `captureState()` returns current view + transport + song
  summary. These are scrapdaw's producers; the module supplies the ring.
- **Ingest endpoint:** scrapdaw's `scripts/serve.js` is a tiny static server — the
  cheapest path is to add the FEEDBACK_ROUTES handler there (import the generalized
  `feedback-store.js`, write to `test-results/uploads/`), OR run the standalone
  service. Its deploy is a systemd unit (`deploy/scrapdaw-preview.service`), not
  Docker — favors the in-process route or a second systemd unit over a container.
  Decision belongs to the scrapdaw agent + owner (§7).
- scrapdaw already symlinks devloop scripts (`scripts/gh-ops.sh@`, `gh-file-issue.sh@`)
  — so consuming devloop's module via the same symlink/vendor pattern is consistent
  with how it already depends on devloop. (devloop is not npm-published.)

## 6. Slicing (bot-sized, independently landable)

Order and blast radius. Devloop is CLEAN (no live agent) — S1–S4 are safe to build
there now. scrapdaw has a LIVE agent — S5 is that agent's job; this plan hands it a
finished, documented interface and must NOT touch scrapdaw's tree.

- **S1 — Module scaffold (devloop).** `services/web-feedback/` dir; client entry +
  types; copy+rename `feedback-store.js` generically; unit tests for `rings.ts`
  (age/entry caps, quota drop) and `scrub.ts` (pattern coverage). No behavior change to
  mobissh. Independently landable.
- **S2 — Client capture + rings API (devloop).** `capture.ts`, `report.ts`,
  `auto-upload.ts`, `createFeedback()` wiring, scrubbers applied. Tests: payload shape,
  throttle dedupe, scrub-before-POST. Landable behind no consumer.
- **S3 — Server ingest generalization (devloop).** Extract `extras` seam from
  `saveBugReport`; standalone `service/index.js` + `docker/Dockerfile` + `/healthz`.
  SYNERGY: it writes `test-results/uploads/`, which `services/testhost/server.js`
  already lists and renders (`server.js:42-44,537-556`) — the viewer is free. Tests:
  filename contract, size caps, retention no-op at 0.
- **S4 — Freshness helper (devloop).** SW template + no-store snippet + `/clear`
  recovery template + build-rev cache-name doc. Test: template renders with a given
  slug/rev; SW skips no-store caching.
- **S5 — scrapdaw adoption (scrapdaw agent, NOT here).** Wire trigger, its rings,
  `captureState`, endpoint, SW swap. Prereq: S1–S4 landed. Hand the agent this doc +
  the module interface; do not modify its working tree from this arc.

Each slice merges to devloop `main` before the next; mobissh migration to consume the
shared module (replacing its four `public/modules/*` + `feedback-store.js`) is a
SEPARATE, optional follow-up arc (mobissh keeps its terminal extras as host-registered).

## 7. Open questions (owner / scrapdaw agent)

1. **Deploy model:** shared feedback-service container (mobissh #997 precedent: one
   Tailscale endpoint, proxy + fail-open, all apps' uploads land in one dir the
   orchestrator watches) vs per-app in-process route (simpler for scrapdaw's static
   systemd preview; no container). Centralized viewing vs per-app isolation.
2. **Auth posture:** tailnet-only (mobissh model, no app-level auth) vs a shared token.
   Matters for scrapdaw because its preview binds `0.0.0.0`.
3. **Retention:** keep-all default (mobissh: "storage is cheap, owner keeps traces")
   vs a per-app day cap via `RETENTION_DAYS`.
4. **Screenshot secret redaction:** ship the optional mask-selector seam? require a
   confirm-preview step? or host's problem?
5. **Console capture:** module taps `console.*` globally (intrusive, catches
   everything) vs host feeds `getConsoleLog()` from its own buffer (clean, opt-in).
6. **Module consumption mechanism:** git submodule / vendored copy / symlink (matches
   scrapdaw's existing `scripts/*.sh@` symlinks) — devloop isn't npm-published.
</content>
</invoke>
