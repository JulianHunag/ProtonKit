# ProtonKit

A native macOS Proton Mail client built with pure Swift and SwiftUI. No Proton Bridge required, no paid subscription needed.

ProtonKit directly interfaces with the Proton REST API, implementing SRP-6a authentication (Proton's non-standard variant), PGP encryption/decryption, and token-based key hierarchy from scratch in Swift.

## Features

- **SRP-6a Authentication** - Full Proton SRP variant (little-endian, 4xSHA512 expandHash, bcrypt password hashing)
- **TOTP 2FA** support
- **PGP Encryption/Decryption** - Email encryption via ObjectivePGP with per-key passphrase mapping, supports both RSA and Curve25519 (ECDH) keys
- **Token-based Key Hierarchy** - User key -> address key via encrypted token
- **Multi-Account** - Outlook-style sidebar with per-account folder trees, independent sessions
- **macOS Notifications** - Background polling with native notifications, click-to-navigate, dock badge
- **Session Persistence** - macOS Keychain with namespace isolation per account, automatic restore on launch
- **Three-Pane Layout** - NavigationSplitView (folders / message list / message detail)
- **Infinite Scroll** - Paginated message loading (50 per page)
- **HTML Rendering** - WKWebView with sanitization, auto-height, link interception
- **Delete / Mark Unread** - Trash messages, toggle read/unread via context menu, swipe, toolbar, or keyboard
- **Batch Select & Delete** - Cmd+Click / Shift+Click multi-select with batch trash (toolbar, keyboard, or context menu)
- **Attachment Download** - Download and decrypt PGP-encrypted attachments with save dialog
- **Attachment Upload** - PGP-encrypted attachment upload with per-recipient session key management (RSA + ECDH)
- **Search** - Keyword search across messages via Proton API
- **Keyboard Shortcuts** - Cmd+R refresh, Delete trash, Cmd+Shift+U toggle read/unread, Cmd+D save draft
- **Reply / Reply All / Forward / Compose** - PGP-encrypted email sending with end-to-end encryption for Proton recipients, cleartext for external recipients
- **Forward with HTML** - Forwards preserve original HTML body formatting
- **Save & Edit Drafts** - Save drafts (Cmd+D), edit and send from Drafts folder with attachment preservation
- **Event-based Polling** - Incremental event polling (30s) for near real-time new mail detection

## Screenshots

*Coming soon*

## Requirements

- macOS 14+ (Sonoma)
- Apple Silicon (arm64)
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```bash
git clone https://github.com/JulianHunag/ProtonKit.git
cd ProtonKit

# Debug build + package
bash scripts/build-app.sh
open /Applications/ProtonKit.app
```

For release DMG:
```bash
bash scripts/build-dmg.sh
# Output: build/ProtonKit.dmg
```

Since the app is ad-hoc signed (no Apple Developer certificate), you may need:
```bash
xattr -cr /Applications/ProtonKit.app
```

## Tech Stack

| Component | Choice | Notes |
|-----------|--------|-------|
| Language | Swift 5.9+ | Pure Swift, no ObjC |
| UI | SwiftUI (macOS 14+) | NavigationSplitView |
| PGP | ObjectivePGP 0.99.4 | BSD, SPM via xcframework |
| SRP BigNum | BigInt 5.3+ | MIT, pure Swift |
| Crypto | CryptoKit | X25519 ECDH, built-in |
| Build | SPM + bash scripts | No Xcode GUI required |
| Signing | Ad-hoc | No Apple Developer cert |

## Architecture

```
ProtonKit/
├── Sources/ProtonCore/          # Core library (SRP, API, crypto, session)
│   ├── ProtonSRP/               # SRP-6a authentication (Proton variant)
│   ├── ProtonAPI/               # REST API client (actor-based)
│   ├── ProtonCrypto/            # PGP encryption/decryption, attachment crypto, key passphrase
│   ├── Models/                  # API response models
│   └── Session/                 # Multi-account session management + Keychain
├── Sources/ProtonKit/           # SwiftUI application layer
│   ├── App/                     # App entry, ContentView
│   ├── Services/                # Notification polling service
│   └── Views/                   # Auth, Sidebar, MessageList, MessageDetail, Compose
└── scripts/                     # Build & packaging scripts
```

Key design decisions:
- Each account has its own `ProtonClient` (actor) and `MessageDecryptor` - fully isolated
- Keychain credentials namespaced by account UID (`{uid}.accessToken`)
- Attachment encryption uses self-managed session keys with per-recipient key packets (RSA + ECDH)
- SRP implementation ported from [go-srp](https://github.com/ProtonMail/go-srp) and [hydroxide](https://github.com/emersion/hydroxide)

## References

- [ProtonMail/go-srp](https://github.com/ProtonMail/go-srp) - SRP reference implementation (Go)
- [emersion/hydroxide](https://github.com/emersion/hydroxide) - Open-source Proton Mail Bridge (Go)
- [ObjectivePGP](https://github.com/nickelhuang/ObjectivePGP) - PGP library
- Proton API behavior reverse-engineered from hydroxide source + network inspection

## License

MIT
