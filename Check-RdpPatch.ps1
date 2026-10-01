<#
.SYNOPSIS
    Check for the RDP-hang bug (September 2026) and its fix per Windows build.

.DESCRIPTION
    Detects OS build, decides whether it is Server or Client,
    checks for the problematic update and the OOB fix,
    prints a clear verdict and (if needed) a download link.

    Detection uses four sources, in order of reliability:
      1. Registry UBR        — primary, sees LCU/SSU bundles
      2. Get-HotFix          — classic QFE/KB list
      3. WUA COM history     — Microsoft.Update.Session installation log
      4. DISM package match  — legacy KB package names (not LCU bundles)

    UBR is the most reliable method for cumulative updates, as it is
    always updated by LCU installation even when other sources miss it.

    ProductType is used for accurate Server vs. Client detection,
    independent of OS caption localization.

    Builds are split into three tiers:
      - Supported  : September 2026 RDP matrix (KB check performed)
      - Legacy     : out of servicing before Sept 2026 (no KB check)
      - Unknown    : not in our maps (no KB check)

.PARAMETER OpenLink
    Open the Microsoft Update Catalog link in the default browser
    if the fix is required but not installed.

.NOTES
    Author:  fixsys-spb
    GitHub:  https://github.com/fixsys-spb/Operpatch
    Date:    2026-10-01
    Version: 1.1.0
    License: MIT (see LICENSE)
    Supports:
      Server: 2012, 2012 R2, 2016, 2019, 2022, 2025
      Client: Windows 10 (1607 LTSB, 1809 LTSC, 21H2, 22H2),
              Windows 11 (23H2, 24H2, 25H2, 26H1)
#>

[CmdletBinding()]
param(
    [switch]$OpenLink
)

# --- Colored output helpers ---
function Write-Info { param($m) Write-Host $m -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host $m -ForegroundColor Green }
function Write-Warn { param($m) Write-Host $m -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host $m -ForegroundColor Red }
function Write-Dim  { param($m) Write-Host $m -ForegroundColor DarkGray }

# --- Get current UBR from registry ---
function Get-CurrentUbr {
    try {
        $ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).UBR
        if ($null -ne $ubr -and $ubr -is [int]) {
            return $ubr
        }
        return $null
    } catch {
        return $null
    }
}

# --- Get OS ProductType for reliable Server/Client detection ---
# ProductType: 1 = Workstation, 2 = Domain Controller, 3 = Server
function Get-OsProductType {
    try {
        $cim = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        return [int]$cim.ProductType
    } catch {
        return 0
    }
}

# --- Multi-source KB detection ---
function Test-KbInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$KbId,
        [int]$TargetUbr = 0
    )

    if ($KbId -notmatch '^KB\d+$') {
        return [PSCustomObject]@{ Installed = $false; Source = 'none'; Date = $null }
    }

    # Method 1: Registry UBR
    if ($TargetUbr -gt 0) {
        $currentUbr = Get-CurrentUbr
        if ($null -ne $currentUbr -and $currentUbr -ge $TargetUbr) {
            return [PSCustomObject]@{ Installed = $true; Source = 'Registry UBR'; Date = $null }
        }
    }

    # Method 2: Get-HotFix
    try {
        $hotfix = Get-HotFix -Id $KbId -ErrorAction SilentlyContinue
        if ($hotfix) {
            $installDate = $null
            if ($hotfix.InstalledOn) {
                $installDate = [datetime]$hotfix.InstalledOn
            }
            return [PSCustomObject]@{ Installed = $true; Source = 'Get-HotFix'; Date = $installDate }
        }
    } catch { }

    # Method 3: WUA COM history
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $searcher = $session.CreateUpdateSearcher()
        $total    = $searcher.GetTotalHistoryCount()

        if ($total -gt 0) {
            $maxRecords = [Math]::Min($total, 1000)
            $history    = $searcher.QueryHistory(0, $maxRecords)

            $match = $history |
                     Where-Object { $_.Title -match [regex]::Escape($KbId) } |
                     Sort-Object Date -Descending |
                     Select-Object -First 1

            if ($match) {
                $instDate = $null
                if ($match.Date) {
                    $instDate = [datetime]$match.Date
                }
                return [PSCustomObject]@{ Installed = $true; Source = 'WUA History'; Date = $instDate }
            }
        }
    } catch { }

    # Method 4: DISM package name match (legacy packages only)
    # Note: LCU/SSU bundles are named "Package_for_RollupFix~...~build.ubr"
    # and are detected via Registry UBR (Method 1), not here.
    try {
        $dismOutput = & dism.exe /online /get-packages 2>$null
        if ($dismOutput -and $dismOutput -match "Package_for_$([regex]::Escape($KbId))\b") {
            return [PSCustomObject]@{ Installed = $true; Source = 'DISM'; Date = $null }
        }
    } catch { }

    return [PSCustomObject]@{ Installed = $false; Source = 'none'; Date = $null }
}

# ================= LEGACY / UNSUPPORTED BUILDS =================
# Builds that were out of servicing before September 2026.
# The September 2026 RDP regression does not target these branches,
# so no KB check is performed. The script prints an explicit
# "out of servicing" message instead of a misleading verdict.
#
# Note: "not affected by the September 2026 RDP bug" is NOT the same
# as "safe". These systems may have other vulnerabilities and may be
# missing years of security updates.

$LegacyBuilds = [ordered]@{
    10240 = "Windows 10 1507 / LTSB 2015"
    10586 = "Windows 10 1511"
    15063 = "Windows 10 1703"
    16299 = "Windows 10 1709"
    17134 = "Windows 10 1803"
    18362 = "Windows 10 1903"
    18363 = "Windows 10 1909"
    19041 = "Windows 10 2004"
    19042 = "Windows 10 20H2"
    19043 = "Windows 10 21H1"
    22000 = "Windows 11 21H2"
    22621 = "Windows 11 22H2"
}

# ================= SUPPORTED: SERVER =================
# Patch maps contain only builds for which Microsoft officially
# documents a problem/fix KB pair for the September 2026 RDP issue.
#
# Policy on UBR values:
#   ProblemUbr / FixUbr are filled only when Microsoft explicitly
#   documents the OS build for that KB in the Update Catalog card.
#   Missing data is 0 — never a guess.
#
# Verified UBRs:
#   Server 2019 (9245/9247), Server 2022 (5622/5631),
#   Server 2025 (33438/33451).
#
# Server 2016: UBR set to 0. Live-server check showed UBR 9339 after
# KB5129239, while the Microsoft catalog lists 9514 for this branch.
# Since the two values do not match, UBR-based detection is disabled
# for build 14393. The script relies on Get-HotFix / WUA history /
# DISM, which have been verified to work on Server 2016.

$ServerPatchMap = @{
    9200  = @{ OS = "Windows Server 2012";    Problem = "KB5123065"; Fix = "KB5129244"; ProblemUbr = 0;     FixUbr = 0 }
    9600  = @{ OS = "Windows Server 2012 R2"; Problem = "KB5123066"; Fix = "KB5129243"; ProblemUbr = 0;     FixUbr = 0 }
    14393 = @{ OS = "Windows Server 2016";    Problem = "KB5123099"; Fix = "KB5129239"; ProblemUbr = 0;     FixUbr = 0 }
    17763 = @{ OS = "Windows Server 2019";    Problem = "KB5122876"; Fix = "KB5129238"; ProblemUbr = 9245;  FixUbr = 9247 }
    20348 = @{ OS = "Windows Server 2022";    Problem = "KB5122882"; Fix = "KB5129237"; ProblemUbr = 5622;  FixUbr = 5631 }
    26100 = @{ OS = "Windows Server 2025";    Problem = "KB5122871"; Fix = "KB5129235"; ProblemUbr = 33438; FixUbr = 33451 }
}

# ================= SUPPORTED: CLIENT =================
# Only builds actively serviced by Microsoft as of September 2026,
# and only builds for which Microsoft explicitly documents a
# problem/fix KB pair for the September 2026 RDP issue.
#
# Verified UBRs:
#   Win10 1809 LTSC (9245/9247),
#   Win10 21H2 (7725/7727), Win10 22H2 (7725/7727),
#   Win11 23H2 (—/7584), Win11 24H2 (9445/9457),
#   Win11 25H2 (9445/9457), Win11 26H1 (2954/2956).
#
# Win10 1607 LTSB: UBR set to 0 — see $ServerPatchMap comment.
#
# Out-of-servicing builds are intentionally absent — see $LegacyBuilds.

$ClientPatchMap = @{
    14393 = @{ OS = "Windows 10 1607 / LTSB 2016"; Problem = "KB5123099"; Fix = "KB5129239"; ProblemUbr = 0;    FixUbr = 0 }
    17763 = @{ OS = "Windows 10 1809 / LTSC 2019"; Problem = "KB5122876"; Fix = "KB5129238"; ProblemUbr = 9245; FixUbr = 9247 }
    19044 = @{ OS = "Windows 10 21H2";             Problem = "KB5122878"; Fix = "KB5129236"; ProblemUbr = 7725; FixUbr = 7727 }
    19045 = @{ OS = "Windows 10 22H2";             Problem = "KB5122878"; Fix = "KB5129236"; ProblemUbr = 7725; FixUbr = 7727 }
    22631 = @{ OS = "Windows 11 23H2";             Problem = "KB5122880"; Fix = "KB5129242"; ProblemUbr = 0;    FixUbr = 7584 }
    26100 = @{ OS = "Windows 11 24H2";             Problem = "KB5124008"; Fix = "KB5129195"; ProblemUbr = 9445; FixUbr = 9457 }
    26200 = @{ OS = "Windows 11 25H2";             Problem = "KB5124008"; Fix = "KB5129195"; ProblemUbr = 9445; FixUbr = 9457 }
    28000 = @{ OS = "Windows 11 26H1";             Problem = "KB5124012"; Fix = "KB5129194"; ProblemUbr = 2954; FixUbr = 2956 }
}

# ======================== MAIN ========================

Write-Info "`n=== RDP patch check (September 2026) ===`n"

# --- 1. Detect OS ---
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop |
          Select-Object Caption, Version, BuildNumber, OSArchitecture
    $build = [int]$os.BuildNumber
} catch {
    Write-Err "Failed to query OS information: $($_.Exception.Message)"
    Write-Dim "`nCheck-RdpPatch v1.1.0  |  (c) 2026 fixsys-spb  |  github.com/fixsys-spb/Operpatch"
    return
}

Write-Host ("OS:           {0}" -f $os.Caption)
Write-Host ("Version:      {0}" -f $os.Version)
Write-Host ("Build:        {0}" -f $build)
Write-Host ("Architecture: {0}" -f $os.OSArchitecture)

$currentUbr = Get-CurrentUbr
if ($null -ne $currentUbr) {
    Write-Host ("UBR:          {0}" -f $currentUbr)
}
Write-Host ""

# --- 2. Choose map based on ProductType (language-independent) ---
$productType = Get-OsProductType
$isServer    = ($productType -eq 2) -or ($productType -eq 3)

if ($isServer) {
    $map = $ServerPatchMap
    Write-Dim "Detected: Server OS (ProductType: $productType)"
} else {
    $map = $ClientPatchMap
    Write-Dim "Detected: Client OS (ProductType: $productType)"
}

# --- 3. Legacy / unsupported build check (client-side only) ---
if (-not $isServer -and $LegacyBuilds.Contains($build)) {
    Write-Host ""
    Write-Warn ("Build {0} — {1}" -f $build, $LegacyBuilds[$build])
    Write-Warn "This build is out of servicing before September 2026."
    Write-Warn "The September 2026 RDP regression does not apply to this branch."
    Write-Host ""
    Write-Dim "No KB check performed — there is no September 2026 RDP patch pair"
    Write-Dim "for this Windows build."
    Write-Host ""
    Write-Dim "Note: this is NOT a safety verdict. The system may have"
    Write-Dim "      other unpatched vulnerabilities."
    Write-Host ""
    Write-Dim "Check-RdpPatch v1.1.0  |  (c) 2026 fixsys-spb  |  github.com/fixsys-spb/Operpatch"
    return
}

if (-not $map.ContainsKey($build)) {
    Write-Warn "No patch data available for build $build."
    Write-Warn "Supported builds: $($map.Keys -join ', ')"
    Write-Host ""
    Write-Warn "This build may be:"
    Write-Warn "  - Not yet affected by the September 2026 RDP bug"
    Write-Warn "  - An insider / preview build"
    Write-Warn "  - A future release not yet covered by this tool"
    Write-Dim "`nCheck-RdpPatch v1.1.0  |  (c) 2026 fixsys-spb  |  github.com/fixsys-spb/Operpatch"
    return
}

# --- 4. Show target info ---
$info = $map[$build]
Write-Info ("Target OS:    {0}" -f $info.OS)
Write-Host ("Problem KB:   {0}" -f $info.Problem)
Write-Host ("Fix KB:       {0}" -f $info.Fix)
Write-Host ""

# --- 5. Check installed updates ---
Write-Dim "--- Checking updates (this may take a moment) ---"
$problemCheck = Test-KbInstalled -KbId $info.Problem -TargetUbr $info.ProblemUbr
$fixCheck     = Test-KbInstalled -KbId $info.Fix     -TargetUbr $info.FixUbr

Write-Host ""
Write-Dim "--- Status ---"
Write-Host ""

if (-not $problemCheck.Installed) {
    # Scenario A: problem update not installed -> safe
    Write-Ok ("[OK] Problem update {0} is NOT installed." -f $info.Problem)
    Write-Ok "This system is NOT affected by the RDP bug."
    Write-Host ""
    Write-Dim ("Note: If Windows Update installs {0} later," -f $info.Problem)
    Write-Dim ("      you will need fix {0} to repair RDP." -f $info.Fix)
}
elseif ($fixCheck.Installed) {
    # Scenario B: problem installed + fix installed -> protected
    Write-Warn ("[!] Problem update {0} IS INSTALLED." -f $info.Problem)
    Write-Warn ("    Detection method: {0}" -f $problemCheck.Source)
    Write-Host ""
    Write-Ok ("[OK] Fix {0} IS INSTALLED." -f $info.Fix)
    Write-Ok ("    Detection method: {0}" -f $fixCheck.Source)
    Write-Host ""
    Write-Ok "System is protected. No action required."
}
else {
    # Scenario C: problem installed, fix missing -> ACTION REQUIRED
    Write-Err ("[!] Problem update {0} IS INSTALLED." -f $info.Problem)
    Write-Err ("    Detection method: {0}" -f $problemCheck.Source)
    Write-Err "    This is the cause of the RDP hang bug."
    Write-Host ""
    Write-Err ("[!] Fix {0} is NOT installed. ACTION REQUIRED." -f $info.Fix)
    Write-Err "    RDP connections may hang or terminate unexpectedly."
}

# --- 6. Show download link and installation guidance ---
if ($info.Fix) {
    $catalogUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=$($info.Fix)"
    Write-Host ""
    Write-Info "Microsoft Update Catalog link:"
    Write-Host $catalogUrl -ForegroundColor Yellow

    if (-not $fixCheck.Installed) {
        Write-Host ""
        Write-Info "Installation steps:"
        Write-Host "  1. Open the link above in your browser"
        Write-Host "  2. Find the package matching your architecture (x64 / ARM64)"
        Write-Host "  3. Download the .msu file"
        Write-Host "  4. Run as Administrator:"
        Write-Host ""
        Write-Host ("     wusa.exe `"C:\Path\To\$($info.Fix)-x64.msu`" /quiet /norestart") -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  5. Restart the system when ready"
        Write-Host ""
        Write-Dim "Tip: install programmatically via PowerShell:"
        Write-Dim "     `$url = '<paste-direct-.msu-link-from-catalog>'"
        Write-Dim ("     `$msu = `"C:\Temp\$($info.Fix).msu`"")
        Write-Dim "     Invoke-WebRequest -Uri `$url -OutFile `$msu"
        Write-Dim "     & wusa.exe `$msu /quiet /norestart"
    }

    if ($OpenLink) {
        Write-Info "`nOpening catalog in browser..."
        try {
            Start-Process $catalogUrl
        } catch {
            Write-Warn "Could not open browser: $($_.Exception.Message)"
            Write-Dim "Please visit the link manually."
        }
    }
}

Write-Host ""
Write-Dim "Check-RdpPatch v1.1.0  |  (c) 2026 fixsys-spb  |  github.com/fixsys-spb/Operpatch"
Write-Host ""