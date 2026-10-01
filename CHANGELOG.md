**English** | [Русский](CHANGELOG.ru.md)

# Changelog

All notable changes to the **Check-RdpPatch** project.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Fixed
- KB detection now uses Registry UBR as primary source. Bundled SSU+LCU packages
  were invisible to Get-HotFix, WUA COM history, and DISM by KB number, causing
  false "not installed" verdicts on Windows Server 2022 (UBR 5622/5631) and
  other builds.

### Added
- README: screenshot of the "system protected" verdict (`Check-RdpPatch-screenshot4.png`).

---

## [1.0.2] — 2026-09-30

### Fixed
- KB detection now uses three independent sources...

### Changed
- Verdict now reports the detection source...

### Fixed
- KB detection now uses three independent sources: `Get-HotFix`, WUA COM history, and DISM.
  Bundled SSU+LCU packages were previously invisible to `Get-HotFix` alone, causing false
  "not installed" verdicts on Windows Server 2022 and other builds.

### Fixed
- KB detection now uses three independent sources: `Get-HotFix`, WUA COM history, and DISM.
  Bundled SSU+LCU packages were previously invisible to `Get-HotFix` alone, causing false
  "not installed" verdicts on Windows Server 2022 and other builds.

---

## [1.0.1] — 2026-09-30

### Added
- Author and license metadata in the script headers:
  - `Author: fixsys-spb`
  - `GitHub: https://github.com/fixsys-spb/Operpatch`
  - `Version: 1.0.1`
  - `License: Internal use`
- Author line in the GUI window: `(c) 2026 fixsys-spb | github.com/fixsys-spb/Operpatch`.
- Copyright line at the end of the console output.
- Download link is now shown in all three verdict scenarios, not only when the fix is required. This lets the user grab the `.msu` in advance if the problematic update has not arrived yet.

### Changed
- GUI RichTextBox now uses line-by-line coloring instead of a single color for the whole verdict. `[OK]` lines are green, `[!]` lines are red, notes are gray. Previously the entire output was rendered in one color, which masked important warnings.
- Console: `Write-Err` (red) replaced with `Write-Warn` (yellow) in the "system protected" scenario — this is not an error, only a warning that the problematic update is present.
- GUI window height increased from 580 to 600 px to fit the new author line.
- All UI elements in the GUI shifted down by 10 px accordingly.

### Fixed
- **GUI: Re-check button did not work.** `$MyInvocation.MyCommand.Path` returns an empty value inside an `Add_Click` script block. Replaced with `$PSCommandPath` for `.ps1` and `[System.Reflection.Assembly]::GetEntryAssembly().Location` for the compiled EXE.
- Removed dead variables `$needsAction` and `$fixKb` — they were set but never read.
- English README now matches the Russian one in structure (build section removed from both).

### Removed
- Build-the-EXE section from `README.md` and `README.ru.md` (kept in `build-exe.ps1` and its inline help).

---

## [1.0.0] — 2026-09-29

### Added

**Console script `Check-RdpPatch.ps1`:**
- OS detection by `BuildNumber` via `Win32_OperatingSystem`.
- Split patch maps: server (`$ServerPatchMap`) and client (`$ClientPatchMap`).
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

### Supported systems

**Server:**
- Windows Server 2012 (build 9200)
- Windows Server 2012 R2 (build 9600)
- Windows Server 2016 (build 14393)
- Windows Server 2019 (build 17763)
- Windows Server 2022 (build 20348)
- Windows Server 2025 (build 26100)

**Client:**
- Windows 10: 1507, 1511, 1607, 1703, 1709, 1803, 1809, 1903, 1909, 2004–22H2, LTSC 2015/2016/2019.
- Windows 11: 21H2, 22H2, 23H2, 24H2, 25H2, 26H1.

### Patch matrix

| OS | Problem update | Fix |
|---|---|---|
| Server 2012 | KB5123065 | KB5129244 |
| Server 2012 R2 | KB5123066 | KB5129243 |
| Server 2016 | KB5123099 | KB5129239 |
| Server 2019 | KB5122876 | KB5129238 |
| Server 2022 | KB5122882 | KB5129237 |
| Server 2025 | KB5122871 | KB5129235 |
| Windows 10 (1507–22H2) | KB5123099 / KB5122876 / KB5122878 | KB5129239 / KB5129238 / KB5129236 |
| Windows 11 (21H2–26H1) | KB5122880 / KB5124008 / KB5124012 | KB5129242 / KB5129195 / KB5129194 |

### Known limitations
- Server 2012 / 2012 R2 are not covered by the GUI (the console version handles them).
- `.msu` links on the Microsoft catalog are dynamic and cannot be bookmarked.
- The EXE built with PS2EXE may be flagged by SmartScreen and antivirus products.

---

## [0.1.0] — 2026-09-29

### Added
- Initial concept of the console script for RDP bug diagnostics.
- Patch map for Server 2016, 2019, 2022.
- Basic status output without a verdict.

### Fixed
- Duplicate `26100` key in the hash table — split into `$ServerPatchMap` and `$ClientPatchMap`.
- Output encoding: Cyrillic replaced with English for correct display in CP866.

---

## Maintenance rules

1. New changes go into the `[Unreleased]` section.
2. On release — bump the version per SemVer:
   - `MAJOR` — incompatible changes.
   - `MINOR` — new backwards-compatible functionality.
   - `PATCH` — backwards-compatible fixes.
3. Categories: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.
4. Release date format — `YYYY-MM-DD`.