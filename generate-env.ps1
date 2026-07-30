# Создаёт .env из .env.example, заполняя пустые *_PASSWORD значениями openssl rand -hex 16.
# Если openssl нет в PATH, используется криптостойкий ГСЧ .NET (результат тот же: 32 hex-символа).
# Использование: .\generate-env.ps1 [-Force]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if ((Test-Path .env) -and -not $Force) {
    Write-Error (".env уже существует - не перезаписываю. " +
        "Новые пароли сломают доступ к данным, уже созданным в volumes. " +
        "Если уверены: .\generate-env.ps1 -Force")
}

$openssl = Get-Command openssl -ErrorAction SilentlyContinue

function New-HexPassword {
    if ($script:openssl) {
        return (& $script:openssl.Source rand -hex 16).Trim()
    }
    $bytes = New-Object byte[] 16
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([BitConverter]::ToString($bytes) -replace '-', '').ToLower()
}

$lines = Get-Content .env.example -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^([A-Za-z0-9_]*PASSWORD)=\s*$') {
        "$($Matches[1])=$(New-HexPassword)"
    } else {
        $_
    }
}

# UTF-8 без BOM: BOM в начале .env ломает имя первой переменной у docker compose
$envPath = Join-Path $PSScriptRoot '.env'
[System.IO.File]::WriteAllLines($envPath, $lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ".env создан. Проверьте BIND_IP и порты перед запуском: docker compose up -d"
