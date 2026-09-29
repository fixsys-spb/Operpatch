<#
.SYNOPSIS
    Проверка наличия проблемных обновлений RDP (сентябрь 2026)
    и их исправлений в зависимости от версии Windows Server.

.DESCRIPTION
    Скрипт определяет версию ОС по BuildNumber, проверяет:
      - установлено ли проблемное обновление (причина зависания RDP);
      - установлено ли исправление (OOB-патч);
      - если исправления нет — выводит ссылку на Microsoft Update Catalog.

.NOTES
    Автор: [ваше имя]
    Дата:  2026-09-29
    ОС:    Windows Server 2016 / 2019 / 2022
#>

[CmdletBinding()]
param(
    [switch]$OpenLink  # Открыть ссылку в браузере, если исправление не установлено
)

# --- Цветной вывод ---
function Write-Info    { param($m) Write-Host $m -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host $m -ForegroundColor Green }
function Write-Warn    { param($m) Write-Host $m -ForegroundColor Yellow }
function Write-Err     { param($m) Write-Host $m -ForegroundColor Red }

# --- Карта соответствия: build -> данные о патчах ---
$PatchMap = @{
    14393 = @{
        OS       = "Windows Server 2016"
        Problem  = "KB5123099"
        Fix      = "KB5129239"
    }
    17763 = @{
        OS       = "Windows Server 2019"
        Problem  = "KB5122876"
        Fix      = "KB5129238"
    }
    20348 = @{
        OS       = "Windows Server 2022"
        Problem  = "KB5122882"
        Fix      = "KB5129237"
    }
}

# --- Определение ОС ---
Write-Info "`n=== Проверка обновлений RDP (сентябрь 2026) ===`n"

$os = Get-CimInstance Win32_OperatingSystem |
      Select-Object Caption, Version, BuildNumber, OSArchitecture

$build = [int]$os.BuildNumber

Write-Host ("ОС:           {0}" -f $os.Caption)
Write-Host ("Версия:       {0}" -f $os.Version)
Write-Host ("Сборка:       {0}" -f $build)
Write-Host ("Архитектура:  {0}" -f $os.OSArchitecture)
Write-Host ""

if (-not $PatchMap.ContainsKey($build)) {
    Write-Warn "Для сборки $build информация о патчах отсутствует."
    Write-Warn "Скрипт поддерживает: 14393 (2016), 17763 (2019), 20348 (2022)."
    return
}

$info = $PatchMap[$build]
Write-Info ("Целевая ОС:   {0}" -f $info.OS)
Write-Host ("Проблемный:   {0}" -f $info.Problem)
Write-Host ("Исправление:  {0}" -f $info.Fix)
Write-Host ""

# --- Проверка проблемного обновления ---
$problemInstalled = Get-HotFix -Id $info.Problem -ErrorAction SilentlyContinue
if ($problemInstalled) {
    Write-Err ("[!] Проблемное обновление {0} УСТАНОВЛЕНО (установлено: {1})." -f `
        $info.Problem, $problemInstalled.InstalledOn)
    Write-Err "    Именно оно вызывает зависание RDP / RDS."
} else {
    Write-Ok ("[OK] Проблемное обновление {0} не найдено." -f $info.Problem)
}

# --- Проверка исправления ---
$fixInstalled = Get-HotFix -Id $info.Fix -ErrorAction SilentlyContinue
if ($fixInstalled) {
    Write-Ok ("[OK] Исправление {0} УСТАНОВЛЕНО (установлено: {1})." -f `
        $info.Fix, $fixInstalled.InstalledOn)
    Write-Host ""
    Write-Ok "Сервер защищён. Дополнительных действий не требуется."
} else {
    Write-Warn ("[!] Исправление {0} НЕ УСТАНОВЛЕНО." -f $info.Fix)
    Write-Host ""

    $catalogUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=$($info.Fix)"
    Write-Info "Ссылка на скачивание в Microsoft Update Catalog:"
    Write-Host $catalogUrl -ForegroundColor Yellow
    Write-Host ""
    Write-Info "Как скачать:"
    Write-Host "  1. Открыть ссылку в браузере."
    Write-Host "  2. Найти пакет для x64 и нажать 'Download'."
    Write-Host "  3. Скопировать актуальную ссылку на .msu и скачать файл."
    Write-Host "  4. Установить:"
    Write-Host "     Start-Process wusa.exe -ArgumentList 'C:\Temp\$($info.Fix).msu /quiet /norestart' -Wait"
    Write-Host "  5. Перезагрузить сервер."

    if ($OpenLink) {
        Write-Info "`nОткрываю ссылку в браузере..."
        Start-Process $catalogUrl
    }
}

Write-Host ""