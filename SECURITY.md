# Security Policy

## Supported Versions

Only the latest release is supported with security updates.

| Version | Supported          |
| ------- | ------------------ |
| 1.1.x   | :white_check_mark: |
| < 1.1   | :x:                |

## Reporting a Vulnerability

If you discover a security issue in Check-RdpPatch, please **do not open a
public GitHub issue**. Instead, use one of the following channels:

1. **GitHub Security Advisories** (preferred):
   https://github.com/fixsys-spb/Operpatch/security/advisories/new

2. **Email:** open an issue at
   https://github.com/fixsys-spb/Operpatch/issues and ask for a private
   contact — do not include vulnerability details in the initial message.

Please include:

- A clear description of the issue.
- Steps to reproduce.
- The affected version (`Check-RdpPatch.exe` properties or
  `Get-FileHash` of the file).
- Any proof-of-concept code or screenshots.

## Response Time

I aim to acknowledge reports within **72 hours** and provide an initial
assessment within **7 days**. Coordinated disclosure is appreciated.

## Scope

In scope:

- The PowerShell source code (`Check-RdpPatch.ps1`, `Check-RdpPatch-GUI.ps1`).
- The compiled `Check-RdpPatch.exe` (when built from this repository).
- The GitHub Actions workflows in `.github/workflows/`.

Out of scope:

- Windows itself, Microsoft Update, or the RDP protocol.
- Third-party antivirus products flagging the PS2EXE wrapper
  (a known PS2EXE behaviour — see README FAQ).
- The Microsoft Update Catalog or its dynamic `.msu` links.