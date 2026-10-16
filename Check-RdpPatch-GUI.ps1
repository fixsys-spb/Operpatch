<#
.SYNOPSIS
    RDP Patch Check - GUI (September 2026 bug).

.DESCRIPTION
    WinForms wrapper for the RDP patch check script.
    Shows status, Microsoft Update Catalog link
    with "Copy link" and "Open in browser" buttons.

    Detection uses five sources, with Registry UBR as primary:
      1. Registry UBR              - sees LCU/SSU bundles
      2. Get-HotFix                - classic QFE/KB list
      3. WUA COM history           - Microsoft.Update.Session installation log
      4. Win32_QuickFixEngineering - CIM-based QFE enumeration (fallback)
      5. DISM package match        - legacy KB package names

    ProductType is used for accurate Server vs. Client detection,
    independent of OS caption localization.

    Builds are split into three tiers:
      - Supported  : September 2026 RDP matrix (KB check performed)
      - Legacy     : out of servicing before Sept 2026 (no KB check)
      - Unknown    : not in our maps (no KB check)

    v1.2.1 changes:
      - Fixed OrderedDictionary.ContainsKey failure in Windows PowerShell
      - Safer verdict order: fix is checked before problem KB absence
      - KB IDs are normalized with Trim().ToUpperInvariant()
      - WUA history matching now uses word boundaries
      - OS detection is hardened with try/catch and null checks
      - Get-HotFix / Win32_QFE results are safely reduced to first object
      - DISM output is cached and protected by timeout
      - Link buttons are enabled only when action is required
      - Clipboard copy has fallback to Set-Clipboard
      - [!] WARNING color rule is now reachable
      - Re-check uses $PSVersionTable.PSEdition instead of $IsCoreCLR

.NOTES
    Author:  fixsys-spb
    GitHub:  https://github.com/fixsys-spb/Operpatch
    Date:    2026-10-16
    Version: 1.2.1
    License: MIT (see LICENSE)

    Supports:
      Server: 2012, 2012 R2, 2016, 2019, 2022, 2025
      Client: Windows 10 (1607 LTSB, 1809 LTSC, 21H2, 22H2),
              Windows 11 (23H2, 24H2, 25H2, 26H1)
#>

#Requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Version = '1.2.1'

# ---------- GUI message helper ----------
function Show-GuiMessage {
    param(
        [Parameter(Mandatory)][string]$Message,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        'RDP Patch Check',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    )
}

# ---------- Admin check ----------
function Test-IsAdmin {
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

# ---------- Get current UBR from registry ----------
function Get-CurrentUbr {
    try {
        $ubr = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).UBR
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Verbose "UBR registry key not found."
        return $null
    }
    catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        Write-Verbose "Access denied reading UBR: $($_.Exception.Message)"
        return $null
    }
    catch {
        Write-Warning "Unexpected error reading UBR: $($_.Exception.Message)"
        return $null
    }

    if ($null -ne $ubr) {
        try {
            return [int]$ubr
        }
        catch {
            Write-Verbose "UBR value is not convertible to int: $ubr"
            return $null
        }
    }

    return $null
}

# ---------- Get OS information in one CIM query ----------
function Get-OsInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop |
              Select-Object -First 1

        if ($null -eq $os) {
            Write-Verbose "Win32_OperatingSystem returned no instance."
            return $null
        }

        try {
            $build = [int]$os.BuildNumber
        }
        catch {
            Write-Verbose "Failed to convert BuildNumber to int: $($_.Exception.Message)"
            return $null
        }

        $productTypeValue = $null
        if ($null -ne $os.ProductType) {
            try {
                $productTypeValue = [int]$os.ProductType
            }
            catch {
                Write-Verbose "Failed to convert ProductType to int: $($_.Exception.Message)"
                $productTypeValue = $null
            }
        }

        return [PSCustomObject]@{
            Caption        = [string]$os.Caption
            Version        = [string]$os.Version
            BuildNumber    = $build
            OSArchitecture = [string]$os.OSArchitecture
            ProductType    = $productTypeValue
        }
    }
    catch {
        Write-Verbose "Failed to query Win32_OperatingSystem: $($_.Exception.Message)"
        return $null
    }
}

# ---------- Cached DISM package list ----------
$script:DismPackageCache = $null

function Get-DismPackageList {
    if ($null -ne $script:DismPackageCache) {
        return $script:DismPackageCache
    }

    try {
        $job = Start-Job -ScriptBlock {
            & dism.exe /online /get-packages 2>$null
        }

        $completed = Wait-Job -Job $job -Timeout 30

        if ($completed) {
            $raw = Receive-Job -Job $job

            if ($null -eq $raw) {
                $script:DismPackageCache = @()
            }
            else {
                $script:DismPackageCache = @($raw)
            }
        }
        else {
            Stop-Job -Job $job
            Write-Verbose "DISM package list timed out."
            $script:DismPackageCache = @()
        }

        Remove-Job -Job $job -Force
    }
    catch {
        Write-Verbose "DISM package list failed: $($_.Exception.Message)"
        $script:DismPackageCache = @()
    }

    return $script:DismPackageCache
}

# ---------- Multi-source KB detection ----------
function Test-KbInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$KbId,
        [int]$TargetUbr = 0,
        [bool]$UbrCheckDisabled = $false,
        [object]$CurrentUbr = $null
    )

    $KbId = $KbId.Trim().ToUpperInvariant()

    if ($KbId -notmatch '^KB\d+$') {
        return [PSCustomObject]@{
            Installed  = $false
            Source     = 'invalid'
            Date       = $null
            Confidence = 'none'
        }
    }

    # Method 1: Registry UBR
    if ($TargetUbr -gt 0 -and -not $UbrCheckDisabled) {
        if ($null -eq $CurrentUbr) {
            $CurrentUbr = Get-CurrentUbr
        }

        if ($null -ne $CurrentUbr) {
            try {
                $currentUbrValue = [int]$CurrentUbr

                if ($currentUbrValue -ge $TargetUbr) {
                    Write-Verbose "UBR threshold matched: current=$currentUbrValue target=$TargetUbr for $KbId"
                    return [PSCustomObject]@{
                        Installed  = $true
                        Source     = 'Registry UBR'
                        Date       = $null
                        Confidence = 'high'
                    }
                }
            }
            catch {
                Write-Verbose "Failed to convert CurrentUbr to int for $KbId : $($_.Exception.Message)"
            }
        }
    }

    # Method 2: Get-HotFix
    try {
        $hotfix = Get-HotFix -Id $KbId -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($hotfix) {
            $installDate = $null

            if ($hotfix.InstalledOn) {
                try {
                    $installDate = [datetime]$hotfix.InstalledOn
                }
                catch {
                    Write-Verbose "Failed to parse InstallDate for $KbId from Get-HotFix: $($_.Exception.Message)"
                }
            }

            return [PSCustomObject]@{
                Installed  = $true
                Source     = 'Get-HotFix'
                Date       = $installDate
                Confidence = 'high'
            }
        }
    }
    catch {
        Write-Verbose "Get-HotFix check failed for $KbId : $($_.Exception.Message)"
    }

    # Method 3: WUA COM history (ResultCode = 2 means Succeeded)
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $searcher = $session.CreateUpdateSearcher()
        $total    = $searcher.GetTotalHistoryCount()

        if ($total -gt 0) {
            $maxRecords = [Math]::Min($total, 1000)

            # QueryHistory returns records oldest-first.
            # Read the newest window, not the oldest one.
            $startIndex = $total - $maxRecords
            $history    = $searcher.QueryHistory($startIndex, $maxRecords)

            $pattern = "\b$([regex]::Escape($KbId))\b"

            $match = $history |
                Where-Object {
                    $_.Title -and
                    $_.Title -match $pattern -and
                    $_.ResultCode -eq 2
                } |
                Sort-Object -Property Date -Descending |
                Select-Object -First 1

            if ($match) {
                $instDate = $null

                if ($match.Date) {
                    try {
                        $instDate = [datetime]$match.Date
                    }
                    catch {
                        Write-Verbose "Failed to parse Date for $KbId from WUA history: $($_.Exception.Message)"
                    }
                }

                return [PSCustomObject]@{
                    Installed  = $true
                    Source     = 'WUA History'
                    Date       = $instDate
                    Confidence = 'high'
                }
            }
        }
    }
    catch {
        Write-Verbose "WUA COM history check failed for $KbId : $($_.Exception.Message)"
    }

    # Method 4: Win32_QuickFixEngineering (CIM-based, works on older systems)
    try {
        $qfe = Get-CimInstance -ClassName Win32_QuickFixEngineering `
                               -Filter "HotFixID='$KbId'" `
                               -ErrorAction Stop |
               Select-Object -First 1

        if ($qfe) {
            $instDate = $null

            if ($qfe.InstalledOn) {
                try {
                    $instDate = [datetime]$qfe.InstalledOn
                }
                catch {
                    Write-Verbose "Failed to parse InstalledOn for $KbId from Win32_QFE: $($_.Exception.Message)"
                }
            }

            return [PSCustomObject]@{
                Installed  = $true
                Source     = 'Win32_QFE'
                Date       = $instDate
                Confidence = 'high'
            }
        }
    }
    catch {
        Write-Verbose "Win32_QFE check failed for $KbId : $($_.Exception.Message)"
    }

    # Method 5: DISM package name match (legacy packages only)
    # Note: LCU/SSU bundles are usually named Package_for_RollupFix~...~build.ubr
    # and are detected via Registry UBR (Method 1), not here.
    try {
        $dismList = Get-DismPackageList

        if ($dismList.Count -gt 0) {
            $dismText    = $dismList -join [Environment]::NewLine
            $dismPattern = "Package_for_$([regex]::Escape($KbId))\b"

            if ($dismText -match $dismPattern) {
                return [PSCustomObject]@{
                    Installed  = $true
                    Source     = 'DISM'
                    Date       = $null
                    Confidence = 'medium'
                }
            }
        }
    }
    catch {
        Write-Verbose "DISM check failed for $KbId : $($_.Exception.Message)"
    }

    # Fallthrough: no source confirmed.
    # If UBR check was disabled for this build, mark confidence as low.
    $confidence = if ($UbrCheckDisabled) { 'low' } else { 'none' }

    return [PSCustomObject]@{
        Installed  = $false
        Source     = 'none'
        Date       = $null
        Confidence = $confidence
    }
}

# ---------- Patch map validation ----------
function Assert-PatchMap {
    param(
        [hashtable]$Map,
        [string]$MapName
    )

    foreach ($build in $Map.Keys) {
        $entry = $Map[$build]

        $problem = if ($entry.Problem) { [string]$entry.Problem } else { '' }
        $fix     = if ($entry.Fix)     { [string]$entry.Fix }     else { '' }

        $problem = $problem.Trim().ToUpperInvariant()
        $fix     = $fix.Trim().ToUpperInvariant()

        $problemUbr = [int]$entry.ProblemUbr
        $fixUbr     = [int]$entry.FixUbr
        $ubrDisabled = [bool]$entry.UbrCheckDisabled

        if ($problem -notmatch '^KB\d+$') {
            throw "$MapName build $build has invalid Problem KB: '$($entry.Problem)'"
        }

        if ($fix -notmatch '^KB\d+$') {
            throw "$MapName build $build has invalid Fix KB: '$($entry.Fix)'"
        }

        if ($problemUbr -lt 0) {
            throw "$MapName build $build has negative ProblemUbr: $problemUbr"
        }

        if ($fixUbr -lt 0) {
            throw "$MapName build $build has negative FixUbr: $fixUbr"
        }

        if ($problemUbr -gt 0 -and $fixUbr -gt 0 -and $fixUbr -le $problemUbr) {
            throw "$MapName build $build has FixUbr ($fixUbr) not greater than ProblemUbr ($problemUbr)"
        }

        if ($ubrDisabled -and ($problemUbr -gt 0 -or $fixUbr -gt 0)) {
            throw "$MapName build $build has UbrCheckDisabled=true but non-zero UBR thresholds"
        }
    }
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
# UbrCheckDisabled: when true, UBR comparison is skipped for this build.
# The verdict will show reduced confidence.
# This applies to Server 2012, 2012 R2, and 2016 where UBR thresholds
# are unreliable due to LCU bundling.

$ServerPatchMap = @{
    9200  = @{ OS = "Windows Server 2012";    Problem = "KB5123065"; Fix = "KB5129244"; ProblemUbr = 0;     FixUbr = 0;     UbrCheckDisabled = $true  }
    9600  = @{ OS = "Windows Server 2012 R2"; Problem = "KB5123066"; Fix = "KB5129243"; ProblemUbr = 0;     FixUbr = 0;     UbrCheckDisabled = $true  }
    14393 = @{ OS = "Windows Server 2016";    Problem = "KB5123099"; Fix = "KB5129239"; ProblemUbr = 0;     FixUbr = 0;     UbrCheckDisabled = $true  }
    17763 = @{ OS = "Windows Server 2019";    Problem = "KB5122876"; Fix = "KB5129238"; ProblemUbr = 9245;  FixUbr = 9247;  UbrCheckDisabled = $false }
    20348 = @{ OS = "Windows Server 2022";    Problem = "KB5122882"; Fix = "KB5129237"; ProblemUbr = 5622;  FixUbr = 5631;  UbrCheckDisabled = $false }
    26100 = @{ OS = "Windows Server 2025";    Problem = "KB5122871"; Fix = "KB5129235"; ProblemUbr = 33438; FixUbr = 33451; UbrCheckDisabled = $false }
}

# ================= SUPPORTED: CLIENT =================
$ClientPatchMap = @{
    14393 = @{ OS = "Windows 10 1607 / LTSB 2016"; Problem = "KB5123099"; Fix = "KB5129239"; ProblemUbr = 0;    FixUbr = 0;    UbrCheckDisabled = $true  }
    17763 = @{ OS = "Windows 10 1809 / LTSC 2019"; Problem = "KB5122876"; Fix = "KB5129238"; ProblemUbr = 9245; FixUbr = 9247; UbrCheckDisabled = $false }
    19044 = @{ OS = "Windows 10 21H2";             Problem = "KB5122878"; Fix = "KB5129236"; ProblemUbr = 7725; FixUbr = 7727; UbrCheckDisabled = $false }
    19045 = @{ OS = "Windows 10 22H2";             Problem = "KB5122878"; Fix = "KB5129236"; ProblemUbr = 7725; FixUbr = 7727; UbrCheckDisabled = $false }
    22631 = @{ OS = "Windows 11 23H2";             Problem = "KB5122880"; Fix = "KB5129242"; ProblemUbr = 0;    FixUbr = 7584; UbrCheckDisabled = $false }
    26100 = @{ OS = "Windows 11 24H2";             Problem = "KB5124008"; Fix = "KB5129195"; ProblemUbr = 9445; FixUbr = 9457; UbrCheckDisabled = $false }
    26200 = @{ OS = "Windows 11 25H2";             Problem = "KB5124008"; Fix = "KB5129195"; ProblemUbr = 9445; FixUbr = 9457; UbrCheckDisabled = $false }
    28000 = @{ OS = "Windows 11 26H1";             Problem = "KB5124012"; Fix = "KB5129194"; ProblemUbr = 2954; FixUbr = 2956; UbrCheckDisabled = $false }
}

# ---------- Prepare status ----------
$statusLines    = New-Object System.Collections.ArrayList
$fixUrl         = ''
$verdictIcon    = '[CHECK] '
$actionRequired = $false

try {
    Assert-PatchMap -Map $ServerPatchMap -MapName 'ServerPatchMap'
    Assert-PatchMap -Map $ClientPatchMap -MapName 'ClientPatchMap'
}
catch {
    Show-GuiMessage -Message ("Patch map validation failed:`r`n`r`n" + $_.Exception.Message) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    return
}

try {
    if (-not (Test-IsAdmin)) {
        [void]$statusLines.Add('Warning: script is not running elevated. DISM and some update history checks may be incomplete.')
        [void]$statusLines.Add('')
    }

    $osInfo = Get-OsInfo

    if (-not $osInfo) {
        Show-GuiMessage -Message "Failed to query OS information.`r`n`r`nCannot determine Windows build." -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    $build       = $osInfo.BuildNumber
    $productType = $osInfo.ProductType

    if ($null -eq $productType -or $productType -notin @(1, 2, 3)) {
        Show-GuiMessage -Message (
            "Cannot determine OS ProductType (Server vs Client).`r`n`r`n" +
            "Server 2025 and Windows 11 24H2 share build 26100 but have " +
            "different fix KBs. Refusing to guess."
        ) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)

        return
    }

    $isServer = ($productType -eq 2) -or ($productType -eq 3)

    if ($isServer) {
        $map = $ServerPatchMap
    }
    else {
        $map = $ClientPatchMap
    }

    $currentUbr = Get-CurrentUbr

    [void]$statusLines.Add(("OS:           {0}" -f $osInfo.Caption))
    [void]$statusLines.Add(("Version:      {0}" -f $osInfo.Version))
    [void]$statusLines.Add(("Build:        {0}" -f $build))
    [void]$statusLines.Add(("Architecture: {0}" -f $osInfo.OSArchitecture))

    if ($null -ne $currentUbr) {
        [void]$statusLines.Add(("UBR:          {0}" -f $currentUbr))
    }

    [void]$statusLines.Add('')

    $detectedKind = if ($isServer) { 'Server' } else { 'Client' }
    [void]$statusLines.Add(("Detected:     {0} OS (ProductType: {1})" -f $detectedKind, $productType))

    # --- Legacy / unsupported build check (client-side only) ---
    # IMPORTANT:
    # Do NOT use $LegacyBuilds.ContainsKey($build) for [ordered]@{}
    # in Windows PowerShell 5.1. Use -contains for compatibility.
    if (-not $isServer -and ($LegacyBuilds.Keys -contains $build)) {
        $verdictIcon = '[LEGACY] '

        [void]$statusLines.Add('')
        [void]$statusLines.Add(("Build {0} - {1}" -f $build, $LegacyBuilds[$build]))
        [void]$statusLines.Add('This build is out of servicing before September 2026.')
        [void]$statusLines.Add('The September 2026 RDP regression does not apply to this branch.')
        [void]$statusLines.Add('')
        [void]$statusLines.Add('No KB check performed - there is no September 2026 RDP')
        [void]$statusLines.Add('patch pair for this Windows build.')
        [void]$statusLines.Add('')
        [void]$statusLines.Add('Note: this is NOT a safety verdict. The system may have')
        [void]$statusLines.Add('      other unpatched vulnerabilities.')
    }
    elseif (-not $map.ContainsKey($build)) {
        $verdictIcon = '[UNKNOWN] '

        [void]$statusLines.Add('')
        [void]$statusLines.Add("No patch data available for build $build.")
        [void]$statusLines.Add('')
        [void]$statusLines.Add('This build may be:')
        [void]$statusLines.Add('  - Not yet affected by the September 2026 RDP bug')
        [void]$statusLines.Add('  - An insider / preview build')
        [void]$statusLines.Add('  - A future release not yet covered by this tool')
    }
    else {
        $info = $map[$build]

        $problemKb = [string]$info.Problem
        $fixKb     = [string]$info.Fix

        $problemKb = $problemKb.Trim().ToUpperInvariant()
        $fixKb     = $fixKb.Trim().ToUpperInvariant()

        $ubrDisabled = [bool]$info.UbrCheckDisabled

        [void]$statusLines.Add(("Target OS:    {0}" -f $info.OS))
        [void]$statusLines.Add(("Problem KB:   {0}" -f $problemKb))
        [void]$statusLines.Add(("Fix KB:       {0}" -f $fixKb))

        if ($ubrDisabled) {
            [void]$statusLines.Add('')
            [void]$statusLines.Add('[!] WARNING: UBR-based detection is disabled for this build.')
            [void]$statusLines.Add('    Detection relies on HotFix/WUA/QFE/DISM only.')
            [void]$statusLines.Add('    False negatives are possible on systems with LCU bundling.')
        }

        [void]$statusLines.Add('')
        [void]$statusLines.Add('--- Status ---')
        [void]$statusLines.Add('')

        $problemCheck = Test-KbInstalled -KbId $problemKb `
                                         -TargetUbr ([int]$info.ProblemUbr) `
                                         -UbrCheckDisabled $ubrDisabled `
                                         -CurrentUbr $currentUbr

        $fixCheck = Test-KbInstalled -KbId $fixKb `
                                     -TargetUbr ([int]$info.FixUbr) `
                                     -UbrCheckDisabled $ubrDisabled `
                                     -CurrentUbr $currentUbr

        if ($problemCheck.Source -eq 'invalid' -or $fixCheck.Source -eq 'invalid') {
            $verdictIcon = '[ERROR] '

            [void]$statusLines.Add('[ERROR] Invalid KB identifier in patch map.')
            [void]$statusLines.Add('Please update the tool or report this issue.')
        }
        elseif ($fixCheck.Installed) {
            # Safer order: if fix is installed, system is protected,
            # even if problem KB detection was inconclusive.
            $verdictIcon = '[PROTECTED] '

            if ($problemCheck.Installed) {
                [void]$statusLines.Add(("[!] Problem update IS installed (via {0})." -f $problemCheck.Source))
            }
            else {
                [void]$statusLines.Add('Note: Problem update was not detected, but the fix is installed.')
            }

            [void]$statusLines.Add(("[OK] Fix IS installed (via {0}). System is protected." -f $fixCheck.Source))
        }
        elseif ($problemCheck.Installed) {
            $verdictIcon    = '[VULNERABLE] '
            $actionRequired = $true

            [void]$statusLines.Add(("[!] Problem update IS installed (via {0})." -f $problemCheck.Source))
            [void]$statusLines.Add('[!] Fix is NOT installed. ACTION REQUIRED.')
            [void]$statusLines.Add('')
            [void]$statusLines.Add('Use the buttons below to download the fix.')

            if ($fixKb) {
                $fixUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=$fixKb"
            }
        }
        else {
            $verdictIcon = '[OK] '

            [void]$statusLines.Add('[OK] Problem update is NOT installed.')

            if ($ubrDisabled) {
                [void]$statusLines.Add('     (Low confidence - UBR check disabled for this build)')
                [void]$statusLines.Add('     No September 2026 problem KB was detected by available sources.')
                [void]$statusLines.Add('     Treat as likely not affected, but re-check after updates/reboot.')
            }
            else {
                [void]$statusLines.Add('     This system is NOT affected by the RDP bug.')
            }

            [void]$statusLines.Add('')
            [void]$statusLines.Add(("Note: if Windows Update installs {0} later," -f $problemKb))
            [void]$statusLines.Add(("      you will need fix {0}." -f $fixKb))
        }
    }
}
catch {
    Show-GuiMessage -Message ("Unexpected error during detection:`r`n`r`n" + $_.Exception.Message) -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    return
}

# ---------- Form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text            = "$verdictIcon" + "RDP Patch Check - September 2026"
$form.Size            = New-Object System.Drawing.Size(720, 650)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.BackColor       = [System.Drawing.Color]::FromArgb(248, 248, 250)
$form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

# Title
$title = New-Object System.Windows.Forms.Label
$title.Text     = "RDP Patch Check"
$title.Font     = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(20, 15)
$title.Size     = New-Object System.Drawing.Size(400, 30)
$form.Controls.Add($title)

# Subtitle
$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text      = "Bug introduced by September 2026 cumulative updates"
$subtitle.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$subtitle.ForeColor = [System.Drawing.Color]::Gray
$subtitle.Location  = New-Object System.Drawing.Point(22, 45)
$subtitle.Size      = New-Object System.Drawing.Size(600, 20)
$form.Controls.Add($subtitle)

# Author line
$author = New-Object System.Windows.Forms.Label
$author.Text      = "v$script:Version  |  (c) 2026 fixsys-spb  |  github.com/fixsys-spb/Operpatch"
$author.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$author.ForeColor = [System.Drawing.Color]::Gray
$author.Location  = New-Object System.Drawing.Point(22, 63)
$author.Size      = New-Object System.Drawing.Size(600, 16)
$form.Controls.Add($author)

# Output RichTextBox with line-by-line coloring
$rtb = New-Object System.Windows.Forms.RichTextBox
$rtb.Location    = New-Object System.Drawing.Point(20, 85)
$rtb.Size        = New-Object System.Drawing.Size(665, 330)
$rtb.ReadOnly    = $true
$rtb.BackColor   = [System.Drawing.Color]::White
$rtb.ForeColor   = [System.Drawing.Color]::Black
$rtb.Font        = New-Object System.Drawing.Font("Consolas", 10)
$rtb.BorderStyle = "FixedSingle"
$rtb.Text        = ""

foreach ($line in $statusLines) {
    $color = [System.Drawing.Color]::Black

    if     ($line -match '^\[OK\]')                  { $color = [System.Drawing.Color]::FromArgb(0, 128, 0) }
    elseif ($line -match '^\[ERROR\]')               { $color = [System.Drawing.Color]::FromArgb(192, 0, 0) }
    elseif ($line -match '^\[!\] WARNING')           { $color = [System.Drawing.Color]::FromArgb(200, 120, 0) }
    elseif ($line -match '^\[!\]')                   { $color = [System.Drawing.Color]::FromArgb(192, 0, 0) }
    elseif ($line -match '^---')                     { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^Note:')                   { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^Warning:')                { $color = [System.Drawing.Color]::FromArgb(160, 120, 0) }
    elseif ($line -match '^     \(')                 { $color = [System.Drawing.Color]::FromArgb(160, 120, 0) }
    elseif ($line -match '^This build may be:')      { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^  -')                     { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^Build \d+ -')             { $color = [System.Drawing.Color]::FromArgb(192, 96, 0) }
    elseif ($line -match 'out of servicing')         { $color = [System.Drawing.Color]::FromArgb(192, 96, 0) }
    elseif ($line -match '^No KB check performed')   { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^No patch data available') { $color = [System.Drawing.Color]::FromArgb(192, 96, 0) }
    elseif ($line -match '^No September 2026 problem KB') { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^Treat as likely')         { $color = [System.Drawing.Color]::Gray }

    $rtb.SelectionStart  = $rtb.TextLength
    $rtb.SelectionLength = 0
    $rtb.SelectionColor  = $color
    $rtb.AppendText($line + "`r`n")
}

$rtb.SelectionStart  = 0
$rtb.SelectionLength = 0
$form.Controls.Add($rtb)

# URL label
$urlLabel = New-Object System.Windows.Forms.Label
$urlLabel.Text     = "Download link:"
$urlLabel.Location = New-Object System.Drawing.Point(20, 440)
$urlLabel.Size     = New-Object System.Drawing.Size(100, 20)
$form.Controls.Add($urlLabel)

# URL TextBox
$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Location  = New-Object System.Drawing.Point(120, 438)
$urlBox.Size      = New-Object System.Drawing.Size(565, 24)
$urlBox.ReadOnly  = $true
$urlBox.Font      = New-Object System.Drawing.Font("Consolas", 9)
$urlBox.Text      = $fixUrl
$urlBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($urlBox)

# Copy button
$copyBtn = New-Object System.Windows.Forms.Button
$copyBtn.Text     = "Copy link"
$copyBtn.Location = New-Object System.Drawing.Point(120, 475)
$copyBtn.Size     = New-Object System.Drawing.Size(120, 32)
$copyBtn.Enabled  = [bool]$fixUrl

$copyBtn.Add_Click({
    if (-not $urlBox.Text) {
        return
    }

    try {
        [System.Windows.Forms.Clipboard]::SetText($urlBox.Text)

        Show-GuiMessage -Message "Link copied to clipboard." -Icon ([System.Windows.Forms.MessageBoxIcon]::Information)
    }
    catch {
        try {
            Set-Clipboard -Value $urlBox.Text

            Show-GuiMessage -Message "Link copied to clipboard." -Icon ([System.Windows.Forms.MessageBoxIcon]::Information)
        }
        catch {
            Show-GuiMessage -Message ("Could not copy link:`r`n`r`n" + $_.Exception.Message) -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }
})

$form.Controls.Add($copyBtn)

# Open button
$openBtn = New-Object System.Windows.Forms.Button
$openBtn.Text     = "Open in browser"
$openBtn.Location = New-Object System.Drawing.Point(250, 475)
$openBtn.Size     = New-Object System.Drawing.Size(140, 32)
$openBtn.Enabled  = [bool]$fixUrl

$openBtn.Add_Click({
    if (-not $urlBox.Text) {
        return
    }

    try {
        Start-Process $urlBox.Text
    }
    catch {
        Show-GuiMessage -Message ("Could not open browser:`r`n`r`n" + $_.Exception.Message) -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})

$form.Controls.Add($openBtn)

# Re-check button - uses current PowerShell host
$rerunBtn = New-Object System.Windows.Forms.Button
$rerunBtn.Text     = "Re-check"
$rerunBtn.Location = New-Object System.Drawing.Point(400, 475)
$rerunBtn.Size     = New-Object System.Drawing.Size(100, 32)

$rerunBtn.Add_Click({
    try {
        $exePath = $null

        if ($PSCommandPath) {
            $exePath = $PSCommandPath
        }

        if (-not $exePath) {
            $entry = [System.Reflection.Assembly]::GetEntryAssembly()

            if ($entry -and $entry.Location) {
                $exePath = $entry.Location
            }
        }

        if ($exePath -and (Test-Path -LiteralPath $exePath)) {
            if ($exePath -match '\.ps1$') {
                # Use the current PowerShell host (pwsh.exe or powershell.exe)
                $psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }

                $psHost = $psExe

                if ($PSHOME) {
                    $candidate = Join-Path -Path $PSHOME -ChildPath $psExe

                    if (Test-Path -LiteralPath $candidate) {
                        $psHost = $candidate
                    }
                }

                Start-Process -FilePath $psHost -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$exePath`""
            }
            else {
                Start-Process -FilePath $exePath
            }

            $form.Close()
        }
        else {
            Show-GuiMessage -Message "Cannot restart automatically. Run Check-RdpPatch manually." -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }
    catch {
        Show-GuiMessage -Message ("Restart failed:`r`n`r`n" + $_.Exception.Message) -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})

$form.Controls.Add($rerunBtn)

# Close button
$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text     = "Close"
$closeBtn.Location = New-Object System.Drawing.Point(585, 520)
$closeBtn.Size     = New-Object System.Drawing.Size(100, 32)
$closeBtn.Add_Click({ $form.Close() })
$form.Controls.Add($closeBtn)

# Bottom hint
$hint = New-Object System.Windows.Forms.Label
$hint.Text      = "Fix must be installed manually from Microsoft Update Catalog, then reboot the system."
$hint.ForeColor = [System.Drawing.Color]::Gray
$hint.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$hint.Location  = New-Object System.Drawing.Point(20, 565)
$hint.Size      = New-Object System.Drawing.Size(660, 20)
$form.Controls.Add($hint)

# Run and properly dispose
try {
    [void]$form.ShowDialog()
}
finally {
    $form.Dispose()
}