# Contributing to Check-RdpPatch

Thanks for considering a contribution. This is a small utility, so the
process is intentionally lightweight.

## Before you start

- Check existing [issues](https://github.com/fixsys-spb/Operpatch/issues)
  and [pull requests](https://github.com/fixsys-spb/Operpatch/pulls)
  to avoid duplicate work.
- For non-trivial changes, open an issue first to discuss the approach.

## Development environment

- **OS:** Windows 10/11 or Windows Server 2016+.
- **PowerShell:** 5.1 or newer (`$PSVersionTable.PSVersion`).
- **PSScriptAnalyzer:** install with

  ```powershell
  Install-Module PSScriptAnalyzer -Scope CurrentUser -Force