<#
.SYNOPSIS
    RDP Patch Check - GUI (September 2026 bug).

.DESCRIPTION
    WinForms-обёртка для скрипта проверки RDP-бага.
    Показывает статус, ссылку на Microsoft Update Catalog
    с кнопками "Copy link" и "Open in browser".
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- Patch maps ----------
$ServerPatchMap = @{
    9200  = @{ OS = "Windows Server 2012";       Problem = "KB5123065"; Fix = "KB5129244" }
    9600  = @{ OS = "Windows Server 2012 R2";    Problem = "KB5123066"; Fix = "KB5129243" }
    14393 = @{ OS = "Windows Server 2016";       Problem = "KB5123099"; Fix = "KB5129239" }
    17763 = @{ OS = "Windows Server 2019";       Problem = "KB5122876"; Fix = "KB5129238" }
    20348 = @{ OS = "Windows Server 2022";       Problem = "KB5122882"; Fix = "KB5129237" }
    26100 = @{ OS = "Windows Server 2025";       Problem = "KB5122871"; Fix = "KB5129235" }
}

$ClientPatchMap = @{
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
    22000 = @{ OS = "Windows 11 21H2";                             Problem = "KB5122880"; Fix = "KB5129242" }
    22621 = @{ OS = "Windows 11 22H2";                             Problem = "KB5122880"; Fix = "KB5129242" }
    22631 = @{ OS = "Windows 11 23H2";                             Problem = "KB5122880"; Fix = "KB5129242" }
    26100 = @{ OS = "Windows 11 24H2";                             Problem = "KB5124008"; Fix = "KB5129195" }
    26200 = @{ OS = "Windows 11 25H2";                             Problem = "KB5124008"; Fix = "KB5129195" }
    27695 = @{ OS = "Windows 11 26H1";                             Problem = "KB5124012"; Fix = "KB5129194" }
}

# ---------- Detection ----------
$os       = Get-CimInstance Win32_OperatingSystem |
            Select-Object Caption, Version, BuildNumber, OSArchitecture
$build    = [int]$os.BuildNumber
$isServer = $os.Caption -match "Server"
$map      = if ($isServer) { $ServerPatchMap } else { $ClientPatchMap }

$statusLines = New-Object System.Collections.ArrayList
$statusColor = "Green"
$fixUrl      = ""
$fixKb       = ""
$needsAction = $false

[void]$statusLines.Add(("OS:           {0}" -f $os.Caption))
[void]$statusLines.Add(("Version:      {0}" -f $os.Version))
[void]$statusLines.Add(("Build:        {0}" -f $build))
[void]$statusLines.Add(("Architecture: {0}" -f $os.OSArchitecture))
[void]$statusLines.Add("")
[void]$statusLines.Add(("Detected:     {0} OS" -f $(if ($isServer) { "Server" } else { "Client" })))

if (-not $map.ContainsKey($build)) {
    [void]$statusLines.Add("")
    [void]$statusLines.Add("No patch info for build $build.")
    $statusColor = "Orange"
}
else {
    $info    = $map[$build]
    $fixKb   = $info.Fix
    $fixUrl  = "https://www.catalog.update.microsoft.com/Search.aspx?q=$($info.Fix)"

    $problem = Get-HotFix -Id $info.Problem -ErrorAction SilentlyContinue
    $fix     = Get-HotFix -Id $info.Fix     -ErrorAction SilentlyContinue

    [void]$statusLines.Add(("Target OS:    {0}" -f $info.OS))
    [void]$statusLines.Add(("Problem KB:   {0}" -f $info.Problem))
    [void]$statusLines.Add(("Fix KB:       {0}" -f $info.Fix))
    [void]$statusLines.Add("")
    [void]$statusLines.Add("--- Status ---")

    if (-not $problem) {
        [void]$statusLines.Add("[OK] Problem update is NOT installed.")
        [void]$statusLines.Add("     This system is NOT affected by the RDP bug.")
        [void]$statusLines.Add("")
        [void]$statusLines.Add(("Note: if Windows Update installs {0} later," -f $info.Problem))
        [void]$statusLines.Add(("      you will need fix {0}." -f $info.Fix))
        $statusColor = "Green"
    }
    elseif ($fix) {
        [void]$statusLines.Add("[!] Problem update IS installed.")
        [void]$statusLines.Add("[OK] Fix IS installed. System is protected.")
        $statusColor = "Green"
    }
    else {
        [void]$statusLines.Add("[!] Problem update IS installed.")
        [void]$statusLines.Add("[!] Fix is NOT installed. ACTION REQUIRED.")
        [void]$statusLines.Add("")
        [void]$statusLines.Add("Use the buttons below to download the fix.")
        $statusColor = "Red"
        $needsAction = $true
    }
}

# ---------- Form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text            = "RDP Patch Check — September 2026"
$form.Size            = New-Object System.Drawing.Size(720, 580)
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

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text     = "Bug introduced by September 2026 cumulative updates"
$subtitle.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$subtitle.ForeColor = [System.Drawing.Color]::Gray
$subtitle.Location = New-Object System.Drawing.Point(22, 45)
$subtitle.Size     = New-Object System.Drawing.Size(600, 20)
$form.Controls.Add($subtitle)

# Output RichTextBox
$rtb = New-Object System.Windows.Forms.RichTextBox
$rtb.Location    = New-Object System.Drawing.Point(20, 75)
$rtb.Size        = New-Object System.Drawing.Size(665, 300)
$rtb.ReadOnly    = $true
$rtb.BackColor   = [System.Drawing.Color]::White
$rtb.ForeColor   = [System.Drawing.Color]::Black
$rtb.Font        = New-Object System.Drawing.Font("Consolas", 10)
$rtb.BorderStyle = "FixedSingle"
$rtb.Text        = ($statusLines -join "`r`n")
$rtb.SelectAll()
$rtb.SelectionColor = [System.Drawing.Color]::FromName($statusColor)
$rtb.SelectionStart  = 0
$rtb.SelectionLength = 0
$form.Controls.Add($rtb)

# URL label
$urlLabel = New-Object System.Windows.Forms.Label
$urlLabel.Text     = "Download link:"
$urlLabel.Location = New-Object System.Drawing.Point(20, 390)
$urlLabel.Size     = New-Object System.Drawing.Size(100, 20)
$form.Controls.Add($urlLabel)

# URL TextBox
$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Location  = New-Object System.Drawing.Point(120, 388)
$urlBox.Size      = New-Object System.Drawing.Size(565, 24)
$urlBox.ReadOnly  = $true
$urlBox.Font      = New-Object System.Drawing.Font("Consolas", 9)
$urlBox.Text      = $fixUrl
$urlBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($urlBox)

# Copy button
$copyBtn = New-Object System.Windows.Forms.Button
$copyBtn.Text     = "Copy link"
$copyBtn.Location = New-Object System.Drawing.Point(120, 425)
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
$openBtn.Location = New-Object System.Drawing.Point(250, 425)
$openBtn.Size     = New-Object System.Drawing.Size(140, 32)
$openBtn.Enabled  = [bool]$fixUrl
$openBtn.Add_Click({
    if ($urlBox.Text) {
        Start-Process $urlBox.Text
    }
})
$form.Controls.Add($openBtn)

# Re-run button (useful after installing the fix)
$rerunBtn = New-Object System.Windows.Forms.Button
$rerunBtn.Text     = "Re-check"
$rerunBtn.Location = New-Object System.Drawing.Point(400, 425)
$rerunBtn.Size     = New-Object System.Drawing.Size(100, 32)
$rerunBtn.Add_Click({
    $exePath = $MyInvocation.MyCommand.Path
    if ($exePath) {
        Start-Process $exePath
        $form.Close()
    }
})
$form.Controls.Add($rerunBtn)

# Close button
$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text     = "Close"
$closeBtn.Location = New-Object System.Drawing.Point(585, 470)
$closeBtn.Size     = New-Object System.Drawing.Size(100, 32)
$closeBtn.Add_Click({ $form.Close() })
$form.Controls.Add($closeBtn)

# Bottom hint
$hint = New-Object System.Windows.Forms.Label
$hint.Text      = "Fix must be installed manually from Microsoft Update Catalog, then reboot the system."
$hint.ForeColor = [System.Drawing.Color]::Gray
$hint.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$hint.Location  = New-Object System.Drawing.Point(20, 510)
$hint.Size      = New-Object System.Drawing.Size(660, 20)
$form.Controls.Add($hint)

# Run
[void]$form.ShowDialog()