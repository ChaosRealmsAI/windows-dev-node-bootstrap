# Purpose: Remove only access and state created by Windows Dev Node Bootstrap.
# Usage: Run through uninstall.cmd; pass -Force only from a deliberate automation.
# Notes: The Windows OpenSSH optional capability is intentionally preserved.

[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

function Get-OptionalStateValue {
    param(
        $State,
        [string]$Name,
        $DefaultValue
    )

    if ($null -eq $State) { return $DefaultValue }
    $property = $State.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
}

try {
    Assert-WindowsDevNodeAdministrator
    if (-not $Force) {
        $confirmation = Read-Host "Type REMOVE to delete the managed account and LAN SSH access"
        if ($confirmation -cne 'REMOVE') {
            Write-Output 'Uninstall cancelled. No changes were made.'
            exit 0
        }
    }

    $paths = Get-WindowsDevNodePaths
    $state = Get-WindowsDevNodeState
    $account = Get-LocalUser -Name $script:WindowsDevNodeAccountName -ErrorAction SilentlyContinue
    if ($null -ne $account) {
        $accountCreatedByTool = $null -ne $state -and [bool](Get-OptionalStateValue -State $state -Name 'accountCreatedByTool' -DefaultValue $false)
        if (-not $accountCreatedByTool -or $account.Description -ne $script:WindowsDevNodeAccountDescription) {
            throw "The local account '$($script:WindowsDevNodeAccountName)' is not proven to be project-owned and was not removed."
        }
    }

    if (Test-Path -LiteralPath $paths.SshConfig -PathType Leaf) {
        $currentConfig = Get-Content -LiteralPath $paths.SshConfig -Raw
        $cleanConfig = Remove-WindowsDevNodeManagedBlock -Content $currentConfig

        if (Test-Path -LiteralPath $paths.SshExecutable -PathType Leaf) {
            $candidateDirectory = if (Test-Path -LiteralPath $paths.StateRoot -PathType Container) { $paths.StateRoot } else { $env:TEMP }
            $candidateConfig = Join-Path $candidateDirectory "WindowsDevNode-sshd_config-remove-$PID"
            try {
                Write-WindowsDevNodeUtf8NoBom -Path $candidateConfig -Content $cleanConfig
                $validationOutput = & $paths.SshExecutable -t -f $candidateConfig 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "The preserved sshd_config is invalid after removing the managed block: $($validationOutput -join ' ')"
                }
            }
            finally {
                Remove-Item -LiteralPath $candidateConfig -Force -ErrorAction SilentlyContinue
            }
        }
        Write-WindowsDevNodeUtf8NoBom -Path $paths.SshConfig -Content $cleanConfig
    }

    $managedRule = Get-NetFirewallRule -Name $script:WindowsDevNodeFirewallRuleName -ErrorAction SilentlyContinue
    if ($null -ne $managedRule) {
        Remove-NetFirewallRule -Name $script:WindowsDevNodeFirewallRuleName
    }

    if ($null -ne $account) {
        Remove-LocalUser -Name $script:WindowsDevNodeAccountName
    }

    $inboxRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    if ($null -ne $inboxRule -and $null -ne $state) {
        $inboxRuleWasEnabled = [bool](Get-OptionalStateValue -State $state -Name 'inboxFirewallRuleWasEnabled' -DefaultValue $false)
        if ($inboxRuleWasEnabled) {
            Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
        }
        else {
            Disable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
        }
    }

    if ($null -ne $state -and [bool](Get-OptionalStateValue -State $state -Name 'networkProfileChanged' -DefaultValue $false)) {
        $interfaceIndex = Get-OptionalStateValue -State $state -Name 'networkInterfaceIndex' -DefaultValue $null
        $previousCategory = [string](Get-OptionalStateValue -State $state -Name 'previousNetworkCategory' -DefaultValue '')
        if ($null -ne $interfaceIndex -and ($previousCategory -eq 'Public' -or $previousCategory -eq 'Private')) {
            $profile = Get-NetConnectionProfile -InterfaceIndex $interfaceIndex -ErrorAction SilentlyContinue
            if ($null -ne $profile) {
                Set-NetConnectionProfile -InterfaceIndex $interfaceIndex -NetworkCategory $previousCategory
            }
        }
    }

    $service = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($null -ne $service) {
        if ($null -ne $state -and [bool](Get-OptionalStateValue -State $state -Name 'sshServiceExistedBefore' -DefaultValue $false)) {
            $previousStartMode = [string](Get-OptionalStateValue -State $state -Name 'sshServicePreviousStartMode' -DefaultValue 'Manual')
            $startupType = switch ($previousStartMode) {
                'Auto' { 'Automatic' }
                'Disabled' { 'Disabled' }
                default { 'Manual' }
            }
            Set-Service -Name sshd -StartupType $startupType
            if ([bool](Get-OptionalStateValue -State $state -Name 'sshServiceWasRunning' -DefaultValue $false)) {
                if ($service.Status.ToString() -eq 'Running') {
                    Restart-Service -Name sshd
                }
                else {
                    Start-Service -Name sshd
                }
            }
            else {
                Stop-Service -Name sshd -ErrorAction SilentlyContinue
            }
        }
        else {
            Stop-Service -Name sshd -ErrorAction SilentlyContinue
            Set-Service -Name sshd -StartupType Manual
        }
    }

    $expectedStateRoot = Join-Path $env:ProgramData 'WindowsDevNode'
    if ($paths.StateRoot -ne $expectedStateRoot) {
        throw 'Refusing to remove an unexpected state directory.'
    }
    if (Test-Path -LiteralPath $paths.StateRoot) {
        Remove-Item -LiteralPath $paths.StateRoot -Recurse -Force
    }

    Write-Output '=== WINDOWS DEV NODE REMOVAL REPORT BEGIN ==='
    Write-Output '{"schemaVersion":1,"status":"REMOVED","openSshCapability":"preserved"}'
    Write-Output '=== WINDOWS DEV NODE REMOVAL REPORT END ==='
    exit 0
}
catch {
    Write-Error "Uninstall failed: $($_.Exception.Message)"
    exit 1
}
