# Security

- **Never store sensitive data (passwords, private keys, passphrases) in plaintext.** Use encrypted storage appropriate to the platform, or don't store at all.
- If secure storage is unavailable, **block the feature**; do not fall back to plaintext storage with a warning.
- No secrets in code, config files, or logs.
- No secrets in commit messages or issue bodies.
