<#
.SYNOPSIS
    Сборка Check-RdpPatch.exe из GUI-скрипта через PS2EXE.

.DESCRIPTION
    - Проверяет наличие модуля ps2exe, устанавливает при отсутствии.
    - Компилирует Check-RdpPatch-GUI.ps1 в Check-RdpPatch.exe.
    - Поддерживает иконку (icon.ico) и метаданные версии.
    - Автоматически читает версию из CHANGELOG.md (первая запись).

.PARAMETER Version
    Версия EXE. Если не указана, берётся из CHANGELOG.md.

.PARAMETER IconPath
    Путь к .ico-файлу. По умолчанию - scripts\icon.ico (если существует).

.PARAMETER SkipInstall
    Не пытаться устанавливать ps2exe, только проверить наличие.

.EXAMPLE
    .\build-exe.ps1
    .\build-exe.ps1 -Version 1.0.1
    .\build-exe.ps1 -IconPath "C:\icons\shield.ico"
#>

[CmdletBinding()]
param(
    [string]$Version,
    [string]$IconPath,
    [switch]$SkipInstall
)

# --- Настройки путей ---
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$InputFile  = Join-Path $ScriptDir "Check-RdpPatch-GUI.ps1"
$OutputFile = Join-Path $ScriptDir "Check-RdpPatch.exe"
$Changelog  = Join-Path $ScriptDir "CHANGELOG.md"

# --- Цветной вывод ---
function Write-Step { param($m) Write-Host "» $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  ✓ $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Fail { param($m) Write-Host "  ✗ $m" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Build Check-RdpPatch.exe ===" -ForegroundColor White
Write-Host ""

# --- 1. Проверка входного файла ---
Write-Step "Проверка входного файла"
if (-not (Test-Path $InputFile)) {
    Write-Fail "Не найден $InputFile"
    exit 1
}
Write-Ok "Найден: $InputFile"

# --- 2. Определение версии ---
Write-Step "Определение версии"
if (-not $Version) {
    if (Test-Path $Changelog) {
        $firstVersionLine = Select-String -Path $Changelog -Pattern '^##\s+\[?([0-9]+\.[0-9]+\.[0-9]+)' |
                            Select-Object -First 1
        if ($firstVersionLine) {
            $Version = $firstVersionLine.Matches[0].Groups[1].Value
            Write-Ok "Версия из CHANGELOG.md: $Version"
        }
    }
}
if (-not $Version) {
    $Version = "1.0.0.0"
    Write-Warn "Версия не определена, используется $Version"
} else {
    # Добавляем .0 в конце для формата AssemblyVersion
    if ($Version -match '^\d+\.\d+\.\d+$') {
        $Version = "$Version.0"
        Write-Ok "Версия приведена к формату: $Version"
    }
}

# --- 3. Проверка/установка ps2exe ---
Write-Step "Проверка модуля ps2exe"
$ps2exe = Get-Module -ListAvailable -Name ps2exe
if (-not $ps2exe) {
    if ($SkipInstall) {
        Write-Fail "ps2exe не установлен (указан -SkipInstall)"
        exit 1
    }
    Write-Warn "ps2exe не найден, устанавливаю..."
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -ErrorAction Stop
        Write-Ok "ps2exe установлен"
    }
    catch {
        Write-Fail "Не удалось установить ps2exe: $($_.Exception.Message)"
        Write-Warn "Попробуйте вручную: Install-Module ps2exe -Scope CurrentUser -Force"
        exit 1
    }
} else {
    Write-Ok "ps2exe уже установлен (версия $($ps2exe.Version))"
}

Import-Module ps2exe -Force

# --- 4. Иконка ---
Write-Step "Проверка иконки"
if (-not $IconPath) {
    $defaultIcon = Join-Path $ScriptDir "icon.ico"
    if (Test-Path $defaultIcon) {
        $IconPath = $defaultIcon
        Write-Ok "Используется иконка: $IconPath"
    } else {
        Write-Warn "icon.ico не найден, EXE будет со стандартной иконкой"
    }
} else {
    if (Test-Path $IconPath) {
        Write-Ok "Используется иконка: $IconPath"
    } else {
        Write-Fail "Указанный файл иконки не найден: $IconPath"
        exit 1
    }
}

# --- 5. Компиляция ---
Write-Step "Компиляция в EXE"

$invokeParams = @{
    InputFile   = $InputFile
    OutputFile  = $OutputFile
    NoConsole   = $true
    STA         = $true
    Title       = "RDP Patch Check"
    Description = "Checks for the September 2026 RDP bug and its fix"
    Company     = "Omnissiah_Toolbox"
    Product     = "RDP Patch Check"
    Version     = $Version
    Copyright   = "$(Get-Date -Format 'yyyy')"
}

if ($IconPath) {
    $invokeParams.IconFile = $IconPath
}

try {
    Invoke-PS2EXE @invokeParams -ErrorAction Stop
    Write-Ok "Компиляция завершена"
}
catch {
    Write-Fail "Ошибка компиляции: $($_.Exception.Message)"
    exit 1
}

# --- 6. Проверка результата ---
Write-Step "Проверка результата"
if (Test-Path $OutputFile) {
    $exeInfo = Get-Item $OutputFile
    $sizeKb  = [math]::Round($exeInfo.Length / 1KB, 1)
    Write-Ok "Файл: $($exeInfo.FullName)"
    Write-Ok "Размер: $sizeKb KB"
    Write-Ok "Создан: $($exeInfo.LastWriteTime)"
    Write-Host ""
    Write-Host "Готово. Можно запускать: $OutputFile" -ForegroundColor White
    Write-Host ""
} else {
    Write-Fail "EXE не создан: $OutputFile"
    exit 1
}