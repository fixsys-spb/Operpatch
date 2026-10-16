**English** | [Русский](CHANGELOG.ru.md)

# Changelog

All notable changes to the **Check-RdpPatch** project.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [Unreleased][]

_No notable changes yet._

---

## [1.2.0][] — 2026-10-16

### Added
- Unified release numbering for the console script, GUI script, and compiled
  EXE. All project artifacts now move together under the same version number.
- Console: startup patch-map validation (`Assert-PatchMap`) to reject malformed
  KB identifiers and inconsistent UBR thresholds before detection runs.
- Console: process exit codes for automation:
  - `0` = OK / protected / not affected;
  - `1` = validation or detection error;
  - `2` = fix required.
- Console and GUI: warning when the script is not running elevated, because
  DISM and some update-history checks may be incomplete without administrator
  rights.
- GUI: `Win32_QuickFixEngineering` CIM query as an additional KB detection
  source.
- GUI: `UbrCheckDisabled` flag for builds where Registry UBR is unreliable:
  - Windows Server 2012;
  - Windows Server 2012 R2;
  - Windows Server 2016;
  - Windows 10 1607 / LTSB 2016.
- GUI: WUA history filtering by `ResultCode = 2`, so only successful
  installations are counted.
- GUI: deterministic form disposal after `ShowDialog()`.
- GUI: Re-check button restarts using the current PowerShell host.
- GUI: DISM detection runs in a background job with a 30-second timeout.
- GUI: clipboard fallback to `Set-Clipboard` when
  `System.Windows.Forms.Clipboard]::SetText()` fails.
- `.gitattributes` to normalize line endings across the repository
  (LF for source and docs, CRLF for `.bat`/`.cmd`, binary for images
  and executables).
- README (EN and RU): "Verified on" section with a summary table of
  live systems tested (Server 2016/2019/2022, Windows 10 22H2), the
  UBR at the time of testing, the resulting verdict, and the detection
  source that produced it.

### Changed
- Console detection remains documented as four sources:
  Registry UBR, `Get-HotFix`, WUA history, and DISM.
- GUI detection is documented as five sources after adding
  `Win32_QuickFixEngineering`.
- Console: KB identifiers are normalized with `Trim().ToUpperInvariant()`
  before validation.
- Console: WUA history matching uses word boundaries to avoid matching
  longer KB numbers.
- Console: `Get-HotFix` results are reduced to the first object and date
  parsing is protected by `try/catch`.
- Console: DISM package list is cached once per run instead of calling
  `dism.exe` separately for each KB.
- Console: OS/ProductType detection uses a single CIM query and refuses
  invalid ProductType values instead of guessing.
- Console: verdict order changed to check the fix before concluding that
  the problem update is absent.
- Console: `-OpenLink` opens the Microsoft Update Catalog only when the
  fix is required and not installed.
- Console: supported build list is sorted in unknown-build diagnostics.
- GUI: verdict order changed to check the fix before concluding that
  the problem update is absent.
- GUI: KB identifiers are normalized before detection.
- GUI: WUA history matching uses word boundaries.
- GUI: `Get-HotFix` and `Win32_QuickFixEngineering` results are reduced
  to the first object and date parsing is protected.
- GUI: DISM package list is cached and protected by a timeout.
- GUI: UBR detection respects `UbrCheckDisabled` and reports reduced
  confidence for builds where UBR thresholds are unreliable.
- GUI: download-link buttons are enabled only when the system is
  vulnerable and action is required.
- GUI: `[!] WARNING` color rule is evaluated before the generic `[!]`
  rule.
- GUI: Re-check button resolves the current PowerShell host via
  `$PSVersionTable.PSEdition` and `$PSHOME`.
- GUI: OS detection and the detection pipeline are wrapped in error
  handling that shows a message box instead of failing in the console.
- Removed all PSScriptAnalyzer warnings:
  - Empty `catch` blocks now log via `Write-Verbose` instead of being
    silent (rule `PSAvoidUsingEmptyCatchBlock`).
  - `Write-Host` usage in the console script is suppressed project-wide
    via `[Diagnostics.CodeAnalysis.SuppressMessageAttribute]`, justified
    by interactive colored output (rule `PSAvoidUsingWriteHost`).
- Cleaned up all Remark-lint warnings in both CHANGELOG files:
  - Added reference-link definitions for every version heading.
  - Switched section headings to collapsed reference form (`[X][]`).
  - Ensured a trailing newline at end of file.
- Documentation corrections:
  - README: console detection source count corrected to "four sources"
    (matches v1.0.4 removal of `Get-WindowsPackage`); GUI source count is
    documented separately because v1.2.0 adds `Win32_QuickFixEngineering`.
  - README: "Verified UBR values" table updated with Server 2025,
    Windows 10 21H2/22H2, Windows 11 23H2/24H2/25H2/26H1 and the
    Server 2016 disablement.
  - README: "Supported systems" section rewritten into three tiers
    (Supported / Legacy / Unknown).
  - README (EN and RU): detection-source enumeration in Step 3 corrected.
    `via Registry UBR` was missing from the list, which contradicted both
    the code and the "Verified UBR values" table below.
  - README (EN and RU): FAQ entry for `Get-HotFix` clarified — the tool
    falls back to Registry UBR when the update is bundled as an LCU and
    does not appear in the QFE list.
- GitHub Code Scanning now reports 0 open alerts across all four tools
  (PSScriptAnalyzer, Remark-lint, and two others).

### Fixed
- GUI: fatal `OrderedDictionary.ContainsKey` failure on Windows PowerShell
  5.1. Legacy build lookup now uses:

  ```powershell
  $LegacyBuilds.Keys -contains $build