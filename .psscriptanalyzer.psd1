@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Console-скрипт для интерактивного запуска с цветным выводом.
        # Write-Host здесь уместен — вывод идёт в терминал, а не в пайплайн.
        'PSAvoidUsingWriteHost'
    )
}
