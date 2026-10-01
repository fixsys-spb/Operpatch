<#
.SYNOPSIS
    RDP Patch Check - GUI (September 2026 bug).

.DESCRIPTION
    WinForms wrapper for the RDP patch check script.
    Shows status, Microsoft Update Catalog link
    with "Copy link" and "Open in browser" buttons.

    Detection uses four sources, with Registry UBR as primary:
      1. Registry UBR        — sees LCU/SSU bundles
      2. Get-HotFix          — classic QFE/KB list
      3. WUA COM history     — Microsoft.Update.Session installation log
      4. DISM package match  — legacy KB package names

    ProductType is used for accurate Server vs. Client detection,
    independent of OS caption localization.

    Builds are split into three tiers:
      - Supported  : September 2026 RDP matrix (KB check performed)
      - Legacy     : out of servicing before Sept 2026 (no KB check)
      - Unknown    : not in our maps (no KB check)

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

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- Get current UBR from registry ----------
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

# ---------- Get OS ProductType for reliable Server/Client detection ----------
# ProductType: 1 = Workstation, 2 = Domain Controller, 3 = Server
function Get-OsProductType {
    try {
        $cim = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        return [int]$cim.ProductType
    } catch {
        return 0
    }
}

# ---------- Multi-source KB detection ----------
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
# The September 2026 RDP regression does not target these branches.
# The GUI prints an explicit "out of servicing" message instead of
# a misleading verdict. No KB check is performed.

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
# UBR policy: ProblemUbr / FixUbr are filled only when Microsoft explicitly
# documents the OS build for that KB in the Update Catalog card.
# Missing data is 0 — never a guess.
#
# Verified UBRs:
#   Server 2019 (9245/9247), Server 2022 (5622/5631),
#   Server 2025 (33438/33451).
#
# Server 2016: UBR set to 0 — live-server check showed 9339 after KB5129239,
# while the Microsoft catalog lists 9514. UBR detection disabled for 14393.

$ServerPatchMap = @{
    9200  = @{ OS = "Windows Server 2012";    Problem = "KB5123065"; Fix = "KB5129244"; ProblemUbr = 0;     FixUbr = 0 }
    9600  = @{ OS = "Windows Server 2012 R2"; Problem = "KB5123066"; Fix = "KB5129243"; ProblemUbr = 0;     FixUbr = 0 }
    14393 = @{ OS = "Windows Server 2016";    Problem = "KB5123099"; Fix = "KB5129239"; ProblemUbr = 0;     FixUbr = 0 }
    17763 = @{ OS = "Windows Server 2019";    Problem = "KB5122876"; Fix = "KB5129238"; ProblemUbr = 9245;  FixUbr = 9247 }
    20348 = @{ OS = "Windows Server 2022";    Problem = "KB5122882"; Fix = "KB5129237"; ProblemUbr = 5622;  FixUbr = 5631 }
    26100 = @{ OS = "Windows Server 2025";    Problem = "KB5122871"; Fix = "KB5129235"; ProblemUbr = 33438; FixUbr = 33451 }
}

# ================= SUPPORTED: CLIENT =================
# Verified UBRs:
#   Win10 1809 LTSC (9245/9247),
#   Win10 21H2 (7725/7727), Win10 22H2 (7725/7727),
#   Win11 23H2 (—/7584), Win11 24H2 (9445/9457),
#   Win11 25H2 (9445/9457), Win11 26H1 (2954/2956).
#
# Win10 1607 LTSB: UBR set to 0 — see $ServerPatchMap comment.

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

# ---------- Detection ----------
$os       = Get-CimInstance Win32_OperatingSystem |
            Select-Object Caption, Version, BuildNumber, OSArchitecture
$build    = [int]$os.BuildNumber
$productType = Get-OsProductType
$isServer = ($productType -eq 2) -or ($productType -eq 3)
$map      = if ($isServer) { $ServerPatchMap } else { $ClientPatchMap }
$currentUbr = Get-CurrentUbr

$statusLines = New-Object System.Collections.ArrayList
$fixUrl      = ""

[void]$statusLines.Add(("OS:           {0}" -f $os.Caption))
[void]$statusLines.Add(("Version:      {0}" -f $os.Version))
[void]$statusLines.Add(("Build:        {0}" -f $build))
[void]$statusLines.Add(("Architecture: {0}" -f $os.OSArchitecture))
if ($null -ne $currentUbr) {
    [void]$statusLines.Add(("UBR:          {0}" -f $currentUbr))
}
[void]$statusLines.Add("")
[void]$statusLines.Add(("Detected:     {0} OS (ProductType: {1})" -f $(if ($isServer) { "Server" } else { "Client" }), $productType))

if (-not $isServer -and $LegacyBuilds.Contains($build)) {
    # Legacy / out-of-servicing build
    [void]$statusLines.Add("")
    [void]$statusLines.Add(("Build {0} — {1}" -f $build, $LegacyBuilds[$build]))
    [void]$statusLines.Add("This build is out of servicing before September 2026.")
    [void]$statusLines.Add("The September 2026 RDP regression does not apply to this branch.")
    [void]$statusLines.Add("")
    [void]$statusLines.Add("No KB check performed — there is no September 2026 RDP")
    [void]$statusLines.Add("patch pair for this Windows build.")
    [void]$statusLines.Add("")
    [void]$statusLines.Add("Note: this is NOT a safety verdict. The system may have")
    [void]$statusLines.Add("      other unpatched vulnerabilities.")
}
elseif (-not $map.ContainsKey($build)) {
    # Unknown build
    [void]$statusLines.Add("")
    [void]$statusLines.Add("No patch data available for build $build.")
    [void]$statusLines.Add("")
    [void]$statusLines.Add("This build may be:")
    [void]$statusLines.Add("  - Not yet affected by the September 2026 RDP bug")
    [void]$statusLines.Add("  - An insider / preview build")
    [void]$statusLines.Add("  - A future release not yet covered by this tool")
}
else {
    # Supported build — perform KB check
    $info    = $map[$build]
    $fixUrl  = "https://www.catalog.update.microsoft.com/Search.aspx?q=$($info.Fix)"

    $problemCheck = Test-KbInstalled -KbId $info.Problem -TargetUbr $info.ProblemUbr
    $fixCheck     = Test-KbInstalled -KbId $info.Fix     -TargetUbr $info.FixUbr

    [void]$statusLines.Add(("Target OS:    {0}" -f $info.OS))
    [void]$statusLines.Add(("Problem KB:   {0}" -f $info.Problem))
    [void]$statusLines.Add(("Fix KB:       {0}" -f $info.Fix))
    [void]$statusLines.Add("")
    [void]$statusLines.Add("--- Status ---")

    if (-not $problemCheck.Installed) {
        [void]$statusLines.Add("[OK] Problem update is NOT installed.")
        [void]$statusLines.Add("     This system is NOT affected by the RDP bug.")
        [void]$statusLines.Add("")
        [void]$statusLines.Add(("Note: if Windows Update installs {0} later," -f $info.Problem))
        [void]$statusLines.Add(("      you will need fix {0}." -f $info.Fix))
    }
    elseif ($fixCheck.Installed) {
        [void]$statusLines.Add(("[!] Problem update IS installed (via {0})." -f $problemCheck.Source))
        [void]$statusLines.Add(("[OK] Fix IS installed (via {0}). System is protected." -f $fixCheck.Source))
    }
    else {
        [void]$statusLines.Add(("[!] Problem update IS installed (via {0})." -f $problemCheck.Source))
        [void]$statusLines.Add("[!] Fix is NOT installed. ACTION REQUIRED.")
        [void]$statusLines.Add("")
        [void]$statusLines.Add("Use the buttons below to download the fix.")
    }
}

# ---------- Form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text            = "RDP Patch Check — September 2026"
$form.Size            = New-Object System.Drawing.Size(720, 620)
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
$author.Text      = "v1.1.0  |  (c) 2026 fixsys-spb  |  github.com/fixsys-spb/Operpatch"
$author.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$author.ForeColor = [System.Drawing.Color]::Gray
$author.Location  = New-Object System.Drawing.Point(22, 63)
$author.Size      = New-Object System.Drawing.Size(600, 16)
$form.Controls.Add($author)

# Output RichTextBox with line-by-line coloring
$rtb = New-Object System.Windows.Forms.RichTextBox
$rtb.Location    = New-Object System.Drawing.Point(20, 85)
$rtb.Size        = New-Object System.Drawing.Size(665, 310)
$rtb.ReadOnly    = $true
$rtb.BackColor   = [System.Drawing.Color]::White
$rtb.ForeColor   = [System.Drawing.Color]::Black
$rtb.Font        = New-Object System.Drawing.Font("Consolas", 10)
$rtb.BorderStyle = "FixedSingle"
$rtb.Text        = ""

foreach ($line in $statusLines) {
    $color = [System.Drawing.Color]::Black
    if     ($line -match '^\[OK\]')                 { $color = [System.Drawing.Color]::FromArgb(0, 128, 0) }
    elseif ($line -match '^\[!\]')                  { $color = [System.Drawing.Color]::FromArgb(192, 0, 0) }
    elseif ($line -match '^---')                    { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^Note:')                  { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^This build may be:')     { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^  -')                    { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^Build \d+ —')            { $color = [System.Drawing.Color]::FromArgb(192, 96, 0) }
    elseif ($line -match 'out of servicing')        { $color = [System.Drawing.Color]::FromArgb(192, 96, 0) }
    elseif ($line -match '^No KB check performed')  { $color = [System.Drawing.Color]::Gray }
    elseif ($line -match '^No patch data available'){ $color = [System.Drawing.Color]::FromArgb(192, 96, 0) }

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
$urlLabel.Location = New-Object System.Drawing.Point(20, 420)
$urlLabel.Size     = New-Object System.Drawing.Size(100, 20)
$form.Controls.Add($urlLabel)

# URL TextBox
$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Location  = New-Object System.Drawing.Point(120, 418)
$urlBox.Size      = New-Object System.Drawing.Size(565, 24)
$urlBox.ReadOnly  = $true
$urlBox.Font      = New-Object System.Drawing.Font("Consolas", 9)
$urlBox.Text      = $fixUrl
$urlBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($urlBox)

# Copy button
$copyBtn = New-Object System.Windows.Forms.Button
$copyBtn.Text     = "Copy link"
$copyBtn.Location = New-Object System.Drawing.Point(120, 455)
$copyBtn.Size     = New-Object System.Drawing.Size(120, 32)
$copyBtn.Enabled  = [bool]$fixUrl
$copyBtn.Add_Click({
    if ($urlBox.Text) {
        [System.Windows.Forms.Clipboard]::SetText($urlBox.Text)
        [System.Windows.Forms.MessageBox]::Show(
            "Link copied to clipboard.",
            "RDP Patch Check",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
})
$form.Controls.Add($copyBtn)

# Open button
$openBtn = New-Object System.Windows.Forms.Button
$openBtn.Text     = "Open in browser"
$openBtn.Location = New-Object System.Drawing.Point(250, 455)
$openBtn.Size     = New-Object System.Drawing.Size(140, 32)
$openBtn.Enabled  = [bool]$fixUrl
$openBtn.Add_Click({
    if ($urlBox.Text) {
        try {
            Start-Process $urlBox.Text
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not open browser: $($_.Exception.Message)",
                "RDP Patch Check",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    }
})
$form.Controls.Add($openBtn)

# Re-check button
$rerunBtn = New-Object System.Windows.Forms.Button
$rerunBtn.Text     = "Re-check"
$rerunBtn.Location = New-Object System.Drawing.Point(400, 455)
$rerunBtn.Size     = New-Object System.Drawing.Size(100, 32)
$rerunBtn.Add_Click({
    $exePath = $null
    if ($PSCommandPath) {
        $exePath = $PSCommandPath
    }
    elseif ([System.Reflection.Assembly]::GetEntryAssembly()) {
        $entry = [System.Reflection.Assembly]::GetEntryAssembly()
        if ($entry) {
            $exePath = $entry.Location
        }
    }

    if ($exePath -and (Test-Path $exePath)) {
        Start-Process -FilePath $exePath
        $form.Close()
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Cannot restart automatically. Run Check-RdpPatch manually.",
            "RDP Patch Check",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
})
$form.Controls.Add($rerunBtn)

# Close button
$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text     = "Close"
$closeBtn.Location = New-Object System.Drawing.Point(585, 500)
$closeBtn.Size     = New-Object System.Drawing.Size(100, 32)
$closeBtn.Add_Click({ $form.Close() })
$form.Controls.Add($closeBtn)

# Bottom hint
$hint = New-Object System.Windows.Forms.Label
$hint.Text      = "Fix must be installed manually from Microsoft Update Catalog, then reboot the system."
$hint.ForeColor = [System.Drawing.Color]::Gray
$hint.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$hint.Location  = New-Object System.Drawing.Point(20, 545)
$hint.Size      = New-Object System.Drawing.Size(660, 20)
$form.Controls.Add($hint)

# Run
[void]$form.ShowDialog()