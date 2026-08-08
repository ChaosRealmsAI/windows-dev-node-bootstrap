# Purpose: Parse every PowerShell script and enforce the repository security contract.
# Usage: pwsh -NoProfile -File tests/Validate-Project.ps1
# Notes: This script is cross-platform and never invokes Windows setup commands.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$requiredFiles = @(
    'AGENTS.md',
    'README.md',
    'bootstrap.ps1',
    'install.cmd',
    'diagnose.cmd',
    'uninstall.cmd',
    'config/codex_authorized_key.pub',
    'privacy/spec/README.md',
    'privacy/spec/spec-map.md',
    'scripts/windows/Common.ps1',
    'scripts/windows/Install-WindowsDevNode.ps1',
    'scripts/windows/Get-WindowsDevNodeReport.ps1',
    'scripts/windows/Uninstall-WindowsDevNode.ps1'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $projectRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required file: $relativePath"
    }
}

$parseFailures = New-Object System.Collections.Generic.List[string]
$powerShellScripts = @(
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'scripts') -Filter '*.ps1' -Recurse
    Get-Item -LiteralPath (Join-Path $projectRoot 'bootstrap.ps1')
)
$powerShellScripts | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in $errors) {
        $parseFailures.Add("$($_.FullName):$($parseError.Extent.StartLineNumber): $($parseError.Message)")
    }
}

if ($parseFailures.Count -gt 0) {
    throw ($parseFailures -join [Environment]::NewLine)
}

$publicKey = (Get-Content -LiteralPath (Join-Path $projectRoot 'config/codex_authorized_key.pub') -Raw).Trim()
if ($publicKey -notmatch '^ssh-(ed25519|rsa|ecdsa-[^ ]+) [A-Za-z0-9+/=]+(?: [^\r\n]+)?$') {
    throw 'The committed public key is invalid.'
}

$allText = Get-ChildItem -LiteralPath $projectRoot -File -Recurse |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw } |
    Out-String
if ($allText -match 'BEGIN (OPENSSH|RSA|EC) PRIVATE KEY') {
    throw 'Private-key material is present in the project.'
}

$installer = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/windows/Install-WindowsDevNode.ps1') -Raw
$common = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/windows/Common.ps1') -Raw
foreach ($requiredFragment in @(
    'WindowsDevNode-SSH-In-TCP',
    '-RemoteAddress LocalSubnet',
    'AuthenticationMethods publickey',
    'PasswordAuthentication no',
    'AuthorizedKeysFile .ssh/authorized_keys',
    'Get-WindowsDevNodeUserKeyPaths',
    'PAIRING REPORT BEGIN',
    'PAIRING REPORT END'
)) {
    if (($installer + $common) -notmatch [regex]::Escape($requiredFragment)) {
        throw "Missing security contract fragment: $requiredFragment"
    }
}

if ($common.Contains('AuthorizedKeysFile __PROGRAMDATA__/WindowsDevNode/authorized_keys')) {
    throw 'Standard-user keys must not use the legacy ProgramData path.'
}

if ($installer -match '-Profile\s+Any' -or $installer -match '-RemoteAddress\s+0\.0\.0\.0/0') {
    throw 'A broad inbound network scope is forbidden.'
}

$bootstrap = Get-Content -LiteralPath (Join-Path $projectRoot 'bootstrap.ps1') -Raw
$readme = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw
foreach ($requiredFragment in @(
    'windows-dev-node-bootstrap/archive/refs/heads/main.zip',
    '[guid]::NewGuid()',
    '[BOOTSTRAP 1/4]',
    '[BOOTSTRAP 4/4]',
    '-TimeoutSec 60',
    '-NoExit',
    '-Verb RunAs'
)) {
    if ($bootstrap -notmatch [regex]::Escape($requiredFragment)) {
        throw "Missing bootstrap contract fragment: $requiredFragment"
    }
}

foreach ($requiredFragment in @(
    "Write-Host '[START] Downloading bootstrap...'",
    "bootstrap.ps1' -TimeoutSec 60 | iex"
)) {
    if (-not $readme.Contains($requiredFragment)) {
        throw "README one-line command is missing required fragment: $requiredFragment"
    }
}

. (Join-Path $projectRoot 'scripts/windows/Common.ps1')
$fixtureConfig = @'
Port 22
PubkeyAuthentication yes
Match Group administrators
    AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
'@
$fixtureConfig += [Environment]::NewLine
$configuredOnce = Set-WindowsDevNodeManagedBlock -Content $fixtureConfig -AccountName 'codexdev'
$configuredTwice = Set-WindowsDevNodeManagedBlock -Content $configuredOnce -AccountName 'codexdev'
if ($configuredOnce -cne $configuredTwice) {
    throw 'Managed sshd_config updates are not idempotent.'
}
if ([regex]::Matches($configuredOnce, [regex]::Escape($script:WindowsDevNodeConfigBegin)).Count -ne 1) {
    throw 'Managed sshd_config must contain exactly one project block.'
}
if (-not (Test-WindowsDevNodeManagedBlock -Content $configuredOnce -AccountName 'codexdev')) {
    throw 'The generated managed sshd_config block does not match the key-only contract.'
}
$tamperedConfig = $configuredOnce.Replace('PasswordAuthentication no', 'PasswordAuthentication yes')
if (Test-WindowsDevNodeManagedBlock -Content $tamperedConfig -AccountName 'codexdev') {
    throw 'A weakened managed sshd_config block must not pass readiness validation.'
}
$restoredConfig = Remove-WindowsDevNodeManagedBlock -Content $configuredOnce
if ($restoredConfig -cne $fixtureConfig) {
    throw 'Removing the managed sshd_config block did not preserve unrelated configuration.'
}
$malformedMarkerRejected = $false
try {
    [void](Remove-WindowsDevNodeManagedBlock -Content ($fixtureConfig + $script:WindowsDevNodeConfigBegin))
}
catch {
    $malformedMarkerRejected = $true
}
if (-not $malformedMarkerRejected) {
    throw 'Incomplete managed sshd_config markers must fail closed.'
}

Write-Output 'PowerShell syntax and project contract: PASS'
