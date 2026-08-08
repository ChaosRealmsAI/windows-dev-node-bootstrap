# Purpose: Download the current project and open its installer in elevated Windows PowerShell.
# Usage: irm 'https://raw.githubusercontent.com/ChaosRealmsAI/windows-dev-node-bootstrap/main/bootstrap.ps1' | iex
# Notes: Source is kept in a unique temporary directory because the elevated installer still needs it.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host '[BOOTSTRAP 1/4] Started.' -ForegroundColor Cyan

if ($env:OS -ne 'Windows_NT') {
    throw 'Windows Dev Node Bootstrap must run on Windows.'
}

[Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$archiveUri = 'https://github.com/ChaosRealmsAI/windows-dev-node-bootstrap/archive/refs/heads/main.zip'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('windows-dev-node-' + [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $temporaryRoot 'source.zip'
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

Write-Host '[BOOTSTRAP 2/4] Downloading the current project...'
Invoke-WebRequest -UseBasicParsing -Uri $archiveUri -OutFile $archivePath -TimeoutSec 60
Write-Host '[BOOTSTRAP 3/4] Extracting the project...'
Expand-Archive -Path $archivePath -DestinationPath $temporaryRoot -Force

$installerPath = Join-Path $temporaryRoot 'windows-dev-node-bootstrap-main\scripts\windows\Install-WindowsDevNode.ps1'
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw 'The downloaded archive does not contain the Windows installer.'
}

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $windowsPowerShell = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
}
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    throw 'Windows PowerShell could not be found.'
}

$installerArgument = '"' + $installerPath + '"'
$argumentList = @(
    '-NoLogo'
    '-NoProfile'
    '-NoExit'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    $installerArgument
) -join ' '

Write-Host '[BOOTSTRAP 4/4] Requesting Administrator access...'
Start-Process -FilePath $windowsPowerShell -Verb RunAs -ArgumentList $argumentList | Out-Null
Write-Host 'Approve the Windows UAC prompt. Installation continues with visible logs in the new window.' -ForegroundColor Green
