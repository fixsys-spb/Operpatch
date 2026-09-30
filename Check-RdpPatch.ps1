<#
.SYNOPSIS
    Check for the RDP-hang bug (September 2026) and its fix per Windows build.

.DESCRIPTION
    Detects OS build, decides whether it is Server or Client,
    checks for the problematic update and the OOB fix,
    prints a clear verdict and (if needed) a download link.

.PARAMETER OpenLink
    Open the Microsoft Update Catalog link in the default browser
    if the fix is required but not installed.

.NOTES
    Author:  fixsys-spb
    GitHub:  https://github.com/fixsys-spb/Operpatch
    Date:    2026-09-30
    Version: 1.0.1
    License: Internal use
    Supports:
      Server: 2012, 2012 R2, 2016, 2019, 2022, 2025
      Client: Windows 10 (1507..22H2, LTSC), Windows 11 (21H2..26H1)
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

# --- Patch map: Server OS ---
$ServerPatchMap = @{
    9200  = @{ OS = "Windows Server 2012";       Problem = "KB5123065"; Fix = "KB5129244" }
    9600  = @{ OS = "Windows Server 2012 R2";    Problem = "KB5123066"; Fix = "KB5129243" }
    14393 = @{ OS = "Windows Server 2016";       Problem = "KB5123099"; Fix = "KB5129239" }
    17763 = @{ OS = "Windows Server 2019";       Problem = "KB5122876"; Fix = "KB5129238" }
    20348 = @{ OS = "Windows Server 2022";       Problem = "KB5122882"; Fix = "KB5129237" }
    26100 = @{ OS = "Windows Server 2025";       Problem = "KB5122871"; Fix = "KB5129235" }
}

# --- Patch map: Client OS ---
$ClientPatchMap = @{
    # Windows 10
    10240 = @{ OS = "Windows 10 1507 / LTSB 2015";                 Problem = "KB5123099"; Fix = "KB5129239" }
    10586 = @{ OS = "Windows 10 1511";                             Problem = "KB5123099"; Fix = "KB5129239" }
    14393 = @{ OS = "Windows 10 1607 / LTSB 2016";                 Problem = "KB5123099"; Fix = "KB5129239" }
    15063 = @{ OS = "Windows 10 1703";                             Problem = "KB5122878"; Fix = "KB5129236" }
    16299 = @{ OS = "Windows 10 1709";                             Problem = "KB5122878"; Fix = "KB5129236" }
    17134 = @{ OS = "Windows 10 1803";                             Problem = "KB5122878"; Fix = "KB5129236" }
    17763 = @{ OS = "Windows 10 1809 / LTSC 2019";                 Problem = "KB5122876"; Fix = "KB5129238" }
    18362 = @{ OS = "Windows 10 1903";                             Problem = "KB5122878"; Fix = "KB5129236" }
    18363 = @{ OS = "Windows 10 1909";                             Problem = "KB5122878"; Fix = "KB5129236" }
    19041 = @{ OS = "Windows 10 2004 / 20H2 / 21H1 / 21H2 / 22H2"; Problem = "KB5122878"; Fix = "KB5129236" }
    19042 = @{ OS = "Windows 10 20H2";                             Problem = "KB5122878"; Fix = "KB5129236" }
    19043 = @{ OS = "Windows 10 21H1";                             Problem = "KB5122878"; Fix = "KB5129236" }
    19044 = @{ OS = "Windows 10 21H2";                             Problem = "KB5122878"; Fix = "KB5129236" }
    19045 = @{ OS = "Windows 10 22H2";                             Problem = "KB5122878"; Fix = "KB5129236" }

    # Windows 11
    22000 = @{ OS = "Windows 11 21H2";                             Problem = "KB5122880"; Fix = "KB5129242" }
    22621 = @{ OS = "Windows 11 22H2";                             Problem = "KB5122880"; Fix = "KB5129242" }
    22631 = @{ OS = "Windows 11 23H2";                             Problem = "KB5122880"; Fix = "KB5129242" }
    26100 = @{ OS = "Windows 11 24H2";                             Problem = "KB5124008"; Fix = "KB5129195" }
    26200 = @{ OS = "Windows 11 25H2";                             Problem = "KB5124008"; Fix = "KB5129195" }
    27695 = @{ OS = "Windows 11 26H1";                             Problem = "KB5124012"; Fix = "KB5129194" }
}

# ======================== MAIN ========================

Write-Info "`n=== RDP patch check (September 2026) ===`n"

# --- 1. Detect OS ---
$os = Get-CimInstance Win32_OperatingSystem |
      Select-Object Caption, Version, BuildNumber, OSArchitecture
$build = [int]$os.BuildNumber

Write-Host ("OS:           {0}" -f $os.Caption)
Write-Host ("Version:      {0}" -f $os.Version)
Write-Host ("Build:        {0}" -f $build)
Write-Host ("Architecture: {0}" -f $os.OSArchitecture)
Write-Host ""

# --- 2. Choose map ---
$isServer = $os.Caption -match "Server"
if ($isServer) {
    $map = $ServerPatchMap
    Write-Dim "Detected: Server OS"
} else {
    $map = $ClientPatchMap
    Write-Dim "Detected: Client OS"
}

if (-not $map.ContainsKey($build)) {
    Write-Warn "No patch info for build $build."
    Write-Warn "Supported builds: $($map.Keys -join ', ')"
    Write-Dim "`nCheck-RdpPatch v1.0.1  |  (c) 2026 fixsys-spb  |  github.com/fixsys-spb/Operpatch"
    return
}

# --- 3. Show target info ---
$info = $map[$build]
Write-Info ("Target OS:    {0}" -f $info.OS)
Write-Host ("Problem KB:   {0}" -f $info.Problem)
Write-Host ("Fix KB:       {0}" -f $info.Fix)
Write-Host ""

# --- 4. Check installed updates ---
$problemInstalled = Get-HotFix -Id $info.Problem -ErrorAction SilentlyContinue
$fixInstalled     = Get-HotFix -Id $info.Fix     -ErrorAction SilentlyContinue

Write-Dim "--- Status ---"

if (-not $problemInstalled) {
    # --- Scenario A: problem update not installed -> safe ---
    Write-Ok ("[OK] Problem update {0} is NOT installed." -f $info.Problem)
    Write-Ok "This system is NOT affected by the RDP bug."
    Write-Host ""
    Write-Dim ("Note: If Windows Update installs {0} later," -f $info.Problem)
    Write-Dim ("      you will need fix {0} to repair RDP." -f $info.Fix)
    Write-Host ""
    Write-Dim "Download link is provided in case the problem update arrives later."
}
elseif ($fixInstalled) {
    # --- Scenario B: problem installed + fix installed -> protected ---
    Write-Warn ("[!] Problem update {0} IS INSTALLED ({1})." -f `
        $info.Problem, $problemInstalled.InstalledOn)
    Write-Host ""
    Write-Ok ("[OK] Fix {0} IS INSTALLED ({1})." -f `
        $info.Fix, $fixInstalled.InstalledOn)
    Write-Ok "System is protected. No action required."
}
else {
    # --- Scenario C: problem installed, fix missing -> ACTION REQUIRED ---
    Write-Err ("[!] Problem update {0} IS INSTALLED ({1})." -f `
        $info.Problem, $problemInstalled.InstalledOn)
    Write-Err "    This is the cause of the RDP hang."
    Write-Host ""
    Write-Warn ("[!] Fix {0} is NOT installed. ACTION REQUIRED." -f $info.Fix)
}

# --- 5. Always show download link if fix exists ---
if ($info.Fix) {
    $catalogUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=$($info.Fix)"
    Write-Host ""
    Write-Info "Download link (Microsoft Update Catalog):"
    Write-Host $catalogUrl -ForegroundColor Yellow
    Write-Host ""
    Write-Info "Steps:"
    Write-Host "  1. Open the link, find the x64 package, click Download."
    Write-Host "  2. Copy the real .msu URL and download the file."
    Write-Host "  3. Install:"
    Write-Host "     Start-Process wusa.exe -ArgumentList 'C:\Temp\$($info.Fix).msu /quiet /norestart' -Wait"
    Write-Host "  4. Reboot the system."

    if ($OpenLink) {
        Write-Info "`nOpening catalog in browser..."
        Start-Process $catalogUrl
    }
}

Write-Host ""
Write-Dim "Check-RdpPatch v1.0.1  |  (c) 2026 fixsys-spb  |  github.com/fixsys-spb/Operpatch"
Write-Host ""