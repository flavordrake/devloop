# Web/Mobile: Test Harness Impact from Behavioral Changes

Platform-specific extension of the TRACE behavioral change checklist
(see `rules/trace-contract.md` for the general principle).

## What counts as "initial system state" for web apps

- **Cold start panel/route** — which view loads first (landing page, login, dashboard)
- **Initial DOM elements** — what exists in the document before user interaction
- **Default configuration** — localStorage defaults, feature flags, theme
- **Service worker state** — cached assets, offline behavior
- **PWA install state** — manifest, icons, splash screen

## Test harness categories

| Category | Frequency | Example | Silent break risk |
|----------|-----------|---------|-------------------|
| Unit (Vitest) | Every commit | Module imports, function behavior | Low |
| Headless E2E (Playwright) | Every PR/gate | DOM assertions, navigation | Low |
| Emulator (Appium) | Manual/scheduled | Touch gestures, PWA install, device-specific | **High** |
| Device (real hardware) | Manual only | Biometric, haptic, camera | **Very high** |

## Checklist for web behavioral changes

When a change affects cold-start state:

1. **Headless Playwright fixtures** — do they navigate to a panel that still exists?
   Do they wait for DOM elements that still render on first load?
2. **Appium/emulator fixtures** — do they assume a terminal/canvas/interactive element
   exists before connecting? Do they assume a specific panel is visible?
3. **Visual smoke tests** — do they check for elements that only exist after user action?
4. **PWA install tests** — do they check manifest values that changed?

## Real example

Lobby terminal removal (MobiSSH dae5f66):
- Changed cold start from "terminal panel with xterm canvas" to "Connect panel"
- Headless tests: some passed (navigated to Connect), some expected `.xterm-screen`
- Appium tests: ALL failed — fixture navigated to terminal tab, waited for `.xterm-screen`
- Fix: fixture needs to connect to test-sshd first, then verify terminal
