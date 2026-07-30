# Ручной деплой немедленно: запускается с машины, у которой есть VPN-доступ к серверу.
# Использование: .\deploy\deploy-now.ps1 -Server user@server [-Path /opt/infra]
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [string]$Path = '/opt/infra'
)

$ErrorActionPreference = 'Stop'
ssh $Server "bash '$Path/deploy/autodeploy.sh' --force"
exit $LASTEXITCODE
