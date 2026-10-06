**English** | [Русский](CHANGELOG.ru.md)

# Changelog

All notable changes to the **Check-RdpPatch** project.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [Unreleased][]

### Planned
- Network mode: scan a list of servers via `Invoke-Command`.
- CSV report export.
- Watch mode (`-Watch`).
- Server 2012 / 2012 R2 support in the GUI (already works in the console version).

---

## [1.1.0][] — 2026-10-01

### Added
- Three-tier build classification:
  - **Supported** — September 2026 RDP matrix. KB check is performed.
  - **Legacy** — out of servicing before Sept 2026. Explicit "out of
    servicing" message, no KB check.
  - **Unknown** — build not in our maps. "No patch data available", no
    KB check.
- `$LegacyBuilds` map covering out-of-servicing branches: Windows 10
  1507, 1511, 1703, 1709, 1803, 1903, 1909, 2004, 20H2, 21H1; Windows 11
  21H2, 22H2.
- OS detection via `ProductType` from `Win32_OperatingSystem` — reliable
  on localized Windows installations (Server vs. Client, ProductType 2/3).

### Changed
- Client patch map trimmed to actively serviced builds only. Removed:
  Windows 10 1507, 1511, 1703, 1709, 1803, 1903, 1909, 2004, 20H2, 21H1;
  Windows 11 21H2, 22H2. These branches are not targeted by the September
  2026 LCUs.
- Documented UBR policy: `ProblemUbr` / `FixUbr` are filled only when
  Microsoft's Update Catalog card explicitly states the OS build.
  Missing data is `0` — never a guess.
- `Test-KbInstalled` in the console script aligned with the GUI version:
  KB-format validation, `[regex]::Escape`, `Package_for_KBxxx` filter,
  WUA history capped at 1000 records.
- Registry UBR read now type-checks the returned value.

### Fixed
- Corrected UBR values:
  - Server 2025: `0/0` → `33438/33451` (KB5122871 / KB5129235).
  - Windows 10 21H2 / 22H2: `0/0` → `7725/7727` (KB5122878 / KB5129236).
  - Windows 11 23H2: FixUbr `0` → `7584` (KB5129242).
  - Windows 11 24H2 / 25H2: `0/0` → `9445/9457`
    (KB5124008 / KB5129195).
- Corrected build number for Windows 11 26H1 in the client patch map:
  `27695` → `28000`. The previous value was an insider preview build and
  would never match a retail system.
- Filled in UBR values for Windows 11 26H1: `2954/2956`
  (KB5124012 / KB5129194).
- Reverted UBR values for Windows Server 2016 and Windows 10 1607 LTSB
  2016 back to `0`. Live-server verification showed UBR `9339` after
  KB5129239 installation, while Microsoft catalog lists `9514` — a
  discrepancy that suggests UBR behaves differently for this branch than
  for Server 2019/2022/2025. Detection falls back to `Get-HotFix` /
  WUA history / DISM, which have been verified to work on Server 2016.
- Corrected PowerShell escaping in the inline install example (backslash
  → backtick). Previous version printed literal `\$url` instead of `$url`.
- Browser launch in the GUI wrapped in try/catch — reports an error if
  `Start-Process` fails.

### Verified on live systems
- Windows Server 2016 (build 14393, UBR 9339) — correct verdict via
  `Get-HotFix`.
- Windows Server 2019 (build 17763, UBR 9247) — correct verdict.
- Windows Server 2022 (build 20348, UBR 5631) — correct verdict.
- Windows 10 22H2 (build 19045, UBR 6456) — correct verdict.
- Tested in all three forms: `.ps1`, GUI, compiled EXE.

---

## [1.0.4][] — 2026-10-01

### Fixed
- **Removed the `Get-WindowsPackage` detection method** (previously
  Method 5). It returned `Installed = $true` for any KB whenever at
  least one `RollupFix` package existed in the system, which caused
  false positives — the tool reported problematic updates as installed
  even when they were not. The check now relies on four sources only:
  Registry UBR → Get-HotFix → WUA History → DISM.
- **Corrected Server 2016 fix UBR** based on real-server verification:
  `9514` → `9339`. (Reverted back to `0` in v1.1.0 — see above.)
- **Client-side UBRs disabled** for platforms without verified values.
  Fields `ProblemUbr` / `FixUbr` are now set to `0` for those entries,
  which disables UBR-based detection and lets the other sources decide.

### Changed
- Detection now uses **four sources** instead of five. The removal of
  Method 5 (`Get-WindowsPackage`) eliminates a class of false positives
  while keeping coverage for bundled SSU+LCU packages via Registry UBR.
- Console output now shows installation steps **only when the fix is
  missing**. In the "system protected" scenario, only the download link
  is printed.
- Script headers updated to reflect the new source count
  (`four sources` instead of `five sources`).

### Verified
- **Windows Server 2016** (build 14393, UBR 9339) — correct verdict.
- **Windows Server 2019** (build 17763, UBR 9247) — correct verdict.
- **Windows Server 2022** (build 20348, UBR 5631) — correct verdict.
- **Windows 10 22H2** (build 19045, UBR 6456) — correct verdict.

---

## [1.0.3][] — 2026-10-01

### Fixed
- KB detection now uses the **Registry UBR** as the primary source.
  Bundled SSU+LCU packages are invisible to `Get-HotFix`, WUA COM
  history, and DISM by KB number, which caused false "not installed"
  verdicts on Windows Server 2022 (UBR 5622/5631) and other builds.
- Detection now reports its source (`via Registry UBR`, `via Get-HotFix`,
  `via WUA History`, `via DISM`, or `via Get-WindowsPackage`).

### Added
- `ProblemUbr` and `FixUbr` fields in both patch maps — numeric build
  revisions for precise comparison.
- UBR value is now shown in the header of the console and GUI output.

### Verified
- Windows Server 2022 (build 20348, UBR 5631) — correct verdict.
- Windows Server 2019 (build 17763) — correct verdict.

---

## [1.0.2][] — 2026-09-30

### Added
- README: screenshot of the "system protected" state
  (`Check-RdpPatch-screenshot4.png`).

### Fixed
- KB detection now uses three independent sources: `Get-HotFix`,
  WUA COM history, and DISM. Bundled SSU+LCU packages were previously
  invisible to `Get-HotFix`, which produced false "not installed"
  verdicts on Windows Server 2022 and other builds.
- Verdict now reports the detection source used to identify each KB.

---

## [1.0.1][] — 2026-09-30

### Added
- Author and license metadata in the script headers:
  - `Author: fixsys-spb`
  - `GitHub: https://github.com/fixsys-spb/Operpatch`
  - `Version: 1.0.1`
  - `License: Internal use`
- Author line in the GUI window:
  `(c) 2026 fixsys-spb | github.com/fixsys-spb/Operpatch`.
- Copyright line at the end of the console output.
- Download link is now shown in all three verdict scenarios, not only
  when the fix is required.

### Changed
- GUI RichTextBox now uses line-by-line coloring instead of a single
  color for the whole verdict. `[OK]` lines are green, `[!]` lines are
  red, notes are gray.
- Console: `Write-Err` (red) replaced with `Write-Warn` (yellow) in the
  "system protected" scenario — this is not an error, only a warning.
- GUI window height increased from 580 to 600 px.
- All UI elements in the GUI shifted down by 10 px accordingly.

### Fixed
- **GUI: Re-check button did not work.** `$MyInvocation.MyCommand.Path`
  returns an empty value inside an `Add_Click` script block. Replaced
  with `$PSCommandPath` for `.ps1` and
  `[System.Reflection.Assembly]::GetEntryAssembly().Location` for the
  compiled EXE.
- Removed dead variables `$needsAction` and `$fixKb`.
- English README now matches the Russian one in structure.

### Removed
- Build-the-EXE section from `README.md` and `README.ru.md`.

---

## [1.0.0][] — 2026-09-29

### Added

**Console script `Check-RdpPatch.ps1`:**
- OS detection by `BuildNumber` via `Win32_OperatingSystem`.
- Split patch maps: server (`$ServerPatchMap`) and client
  (`$ClientPatchMap`).
- Problem-update and fix detection via `Get-HotFix`.
- Three-scenario verdict:
  - system not affected by the bug;
  - system protected;
  - fix required.
- Automatic Microsoft Update Catalog link generation.
- `-OpenLink` switch to open the link in the default browser.

**GUI version `Check-RdpPatch-GUI.ps1` (WinForms):**
- Window 720×580 with title and subtitle.
- Color-coded verdict (green / red).
- **Download link** field with the Microsoft Update Catalog URL.
- **Copy link** button — copies the URL to the clipboard.
- **Open in browser** button — opens the link.
- **Re-check** button — reruns the check.
- **Close** button — closes the window.
- Link buttons disabled when no fix is required.

**Documentation:**
- `README.md` — problem description, supported systems, instructions.
- `Check-RdpPatch-screenshot.png` — GUI screenshot.

### Patch matrix

| OS | Problem update | Fix |
|---|---|---|
| Server 2012 | KB5123065 | KB5129244 |
| Server 2012 R2 | KB5123066 | KB5129243 |
| Server 2016 | KB5123099 | KB5129239 |
| Server 2019 | KB5122876 | KB5129238 |
| Server 2022 | KB5122882 | KB5129237 |
| Server 2025 | KB5122871 | KB5129235 |

### Known limitations
- Server 2012 / 2012 R2 are not covered by the GUI.
- `.msu` links on the Microsoft catalog are dynamic.
- The EXE built with PS2EXE may be flagged by SmartScreen.

---

## [0.1.0][] — 2026-09-29

### Added
- Initial concept of the console script for RDP bug diagnostics.
- Patch map for Server 2016, 2019, 2022.
- Basic status output without a verdict.

### Fixed
- Duplicate `26100` key in the hash table — split into
  `$ServerPatchMap` and `$ClientPatchMap`.
- Output encoding: Cyrillic replaced with English for CP866.

---

## Maintenance rules

1. New changes go into the `[Unreleased]` section.
2. On release — bump the version per SemVer:
   - `MAJOR` — incompatible changes.
   - `MINOR` — new backwards-compatible functionality.
   - `PATCH` — backwards-compatible fixes.
3. Categories: **Added**, **Changed**, **Deprecated**, **Removed**,
   **Fixed**, **Security**.
4. Release date format — `YYYY-MM-DD`.

[Unreleased]: https://github.com/fixsys-spb/Operpatch/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/fixsys-spb/Operpatch/compare/v1.0.4...v1.1.0
[1.0.4]: https://github.com/fixsys-spb/Operpatch/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/fixsys-spb/Operpatch/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/fixsys-spb/Operpatch/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/fixsys-spb/Operpatch/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/fixsys-spb/Operpatch/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/fixsys-spb/Operpatch/releases/tag/v0.1.0
