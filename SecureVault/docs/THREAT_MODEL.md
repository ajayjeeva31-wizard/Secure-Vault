# SecureVault threat model

## Assets

- Master password, derived 256-bit session key, TOTP seed, recovery codes.
- Credential passwords, usernames, sites, notes, and encrypted backups.
- Authentication and security event history.

## Controls

- A random per-vault PBKDF2 salt and 310,000 PBKDF2-HMAC-SHA256 rounds derive
  the session key. The verifier is a keyed HMAC, not a copy of the key.
- AES-256-GCM encrypts every entry separately. Each write gets a fresh random
  96-bit nonce; entry IDs are authenticated as additional data.
- Keychain/Keystore-backed storage holds the verifier and encrypted TOTP
  envelope. Credential content is encrypted before it reaches the app-support
  file.
- TOTP follows RFC 6238 with a 30-second period and one-step drift tolerance.
  Login attempts are rate-limited and lockouts increase after repeated groups
  of five failures.
- Recovery codes contain 160 bits of random entropy. Only an independently
  salted SHA-256 hash is stored, and a matched record is removed on use.
- The app discards its session-key reference and plaintext entry list on lock.
  Backgrounding for one minute locks the vault; screenshot protection is
  requested while unlocked.
- Backups authenticate ciphertext with GCM and require the password used at
  export. Password changes create new encrypted records before switching the
  active generation.

## Assumptions and limits

- The device OS, secure storage, random source, Flutter runtime, and app package
  are not compromised. Root/jailbreak, malware, debugger access, OS exploits,
  malicious accessibility services, or a compromised build can expose data.
- Screenshot blocking is platform-dependent and best-effort. It cannot stop a
  second device from photographing the display. Clipboard contents may be read
  by other apps before the clearing timer runs.
- Weak master passwords remain susceptible to offline guessing against copied
  verifier/backup data. The 12-character minimum is not a substitute for a
  unique passphrase.
- A lost master password cannot be reset by SecureVault. Recovery codes can
  satisfy the second factor but do not replace the master password.
- Encrypted backups include vault entries only. The receiving installation
  retains its own authenticator secret and recovery codes.
- Random 96-bit GCM nonces have negligible but nonzero collision probability.
  Keep realistic per-key message volumes and rotate keys if usage grows
  substantially.
- No external penetration test, platform hardening review, cryptographic audit,
  accessibility review, or store-policy review has been completed.

## Data flow

```text
Master password ── PBKDF2-HMAC-SHA256 ──> in-memory key
                                            ├── verify password HMAC
                                            ├── decrypt TOTP seed ── TOTP check
                                            └── AES-256-GCM per entry ──> memory

Keychain/Keystore: verifier + encrypted TOTP + recovery hashes + auth log
App support file: opaque entry IDs + AES-GCM nonce/ciphertext/tag
Export file: PBKDF2 verifier metadata + AES-GCM encrypted entries
```
