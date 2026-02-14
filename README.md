# 🔐 CommandGuard
### Secure Command Verification for Mobile-to-ICS Control

**Luke Arsenault**  
Georgia Institute of Technology

---

## 🚀 Overview

**CommandGuard** is a prototype security architecture that demonstrates how control commands issued from mobile devices can be safely validated, verified, and tested before reaching an industrial control system (ICS).

The project consists of:
- A **SwiftUI-based iOS application** that constructs and cryptographically signs simulated control commands
- A **SwiftUI-based MacOS verification gateway** that validates command authenticity, freshness, and physical safety
- A **lightweight digital twin** used to prevent unsafe cyber-physical actions

---

## 🏗️ System Architecture

```
┌────────────┐     Signed Command     ┌────────────────┐     Validated Command
│   iOS App  │ ───────────────────▶ │  macOS Gateway  │ ───────────────────▶ │  Simulated ICS
└────────────┘                        └────────────────┘
                                           │
                                           ▼
                                   Digital Twin & Safety Checks
```

---

## 📱 iOS Command Application

The iOS app simulates a mobile operator interface for a data center cooling system.

**Supported Parameters**
- Temperature Setpoint (°F)
- Humidity Setpoint (%)
- Fan Speed (%)
- Valve Position (%)
- Equipment Power
- Control Enabled

Each command is canonicalized, signed (ECDSA P-256 / SHA-256), timestamped, nonced, and logged. Below are screenshots showing the UI of the iOS app. 

<a href="CommandGuardApp/images/ios-home.png">
  <img src="CommandGuardApp/images/ios-home.png" width="400">
</a>

<a href="CommandGuardApp/images/ios-history.png">
  <img src="CommandGuardApp/images/ios-history.png" width="400">
</a>


---

## 🖥️ macOS Verification Gateway

The gateway verifies cryptographic authenticity, prevents replay attacks, simulates commands via a digital twin, and enforces safety thresholds before forwarding or blocking commands.

---

## 🧪 Digital Twin & Safety Enforcement

Commands are evaluated against a simulated ICS state to ensure physical safety, not just cryptographic correctness.

---

## 🔒 Security Features

- Canonicalized JSON encoding
- ECDSA P-256 / SHA-256 signatures
- Unique nonce per command
- Timestamp validation
- Centralized enforcement

---

## 🎯 Threats Addressed

- Command tampering
- Replay attacks
- Unauthorized execution
- Unsafe physical actions

---

## 📂 Project Structure

```
├── CommandGuardApp.swift        # App entry point and SwiftData container setup
├── HomeView.swift               # Main UI for building and sending commands
├── HomeViewModel.swift          # State management and send flow orchestration
├── CommandModels.swift          # Command body, envelope, signature models, and helpers
├── CryptoSigner.swift           # Keychain-backed ECDSA P-256 / SHA-256 signer
├── CommandSendService.swift     # Simulated gateway send/response logic
├── GatewayService.swift         # Model for a discovered Bonjour gateway with stable IDs and display names
├── BonjourBrowser.swift         # Bonjour browsing helper that discovers gateway services on the local network
├── GatewayResponse.swift        # Response models for gateway delivery/execution status and NDJSON parsing
├── RecentCommandsView.swift     # Recent command history UI
├── SendStatus.swift             # Send state and status styling helpers
├── Item.swift                   # Default SwiftData model from the Xcode template
├── CommandGuardGatewayApp.swift # macOS gateway app entry point
├── ContentView.swift            # macOS gateway UI (status + inbox)
├── GatewayInbox.swift           # Stores decoded commands for display
├── GatewayListener.swift        # TCP listener that receives NDJSON commands
├── GatewaySignatureVerifier.swift # Verifies signed command envelopes
├── GatewayKeyStore.swift        # Trusted public keys for verification
├── GatewayResponse.swift        # Gateway response payload model
└── images/                      # README screenshots
```

---

## 📌 Scope & Limitations

This is a research prototype using simplified discovery, key management, and modeling.

---

## 📄 License

Academic and research use.

## AI Usage

This file was assisted by AI in making more consice descriptions and beautifying aspects of the ReadMe. All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
