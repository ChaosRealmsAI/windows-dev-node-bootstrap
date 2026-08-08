# Purpose: Install or repair a LAN-only, public-key-authenticated Windows development node.
# Usage: Run through install.cmd from the project root.
# Notes: This script owns only the resources documented in privacy/spec/README.md.

[CmdletBinding()]
param(
    [switch]$DoNotChangeNetworkProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

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

function Assert-LastNativeCommand {
    param([string]$Operation)

    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE."
    }
}

function Save-WindowsDevNodeInstallState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$State
    )

    $State.lastRepairedAtUtc = [DateTime]::UtcNow.ToString('o')
    Write-WindowsDevNodeUtf8NoBom -Path $Path -Content (($State | ConvertTo-Json -Depth 4) + [Environment]::NewLine)
    & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    Assert-LastNativeCommand -Operation 'Securing the managed state file'
}

try {
    Assert-WindowsDevNodeAdministrator
    Write-Output '[INSTALL 1/7] Checking project state and ownership...'
    $paths = Get-WindowsDevNodePaths
    $previousState = Get-WindowsDevNodeState
    if ((Test-Path -LiteralPath $paths.StateRoot) -and $null -eq $previousState) {
        throw "The managed state directory already exists without a valid state file: $($paths.StateRoot)"
    }
    if ($null -eq $previousState) {
        $unexpectedManagedRule = Get-NetFirewallRule -Name $script:WindowsDevNodeFirewallRuleName -ErrorAction SilentlyContinue
        if ($null -ne $unexpectedManagedRule) {
            throw 'The managed firewall rule name already exists without project state. The installer will not take it over.'
        }
        if (Test-Path -LiteralPath $paths.SshConfig -PathType Leaf) {
            $existingSshConfig = Get-Content -LiteralPath $paths.SshConfig -Raw
            if ($existingSshConfig.Contains($script:WindowsDevNodeConfigBegin) -or $existingSshConfig.Contains($script:WindowsDevNodeConfigEnd)) {
                throw 'Managed sshd_config markers already exist without project state. The installer will not take them over.'
            }
        }
    }

    if (-not (Test-Path -LiteralPath $paths.PublicKey -PathType Leaf)) {
        throw 'The bundled SSH public key is missing.'
    }

    $publicKeyLines = @(
        Get-Content -LiteralPath $paths.PublicKey |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_.Length -gt 0 }
    )
    if ($publicKeyLines.Count -ne 1 -or $publicKeyLines[0] -notmatch '^ssh-(ed25519|rsa|ecdsa-[^ ]+) [A-Za-z0-9+/=]+(?: [^\r\n]+)?$') {
        throw 'The bundled SSH public key is not one valid single-line OpenSSH public key.'
    }
    $publicKey = $publicKeyLines[0]

    $capabilityName = 'OpenSSH.Server~~~~0.0.1.0'
    $capabilityBefore = Get-WindowsCapability -Online -Name $capabilityName
    $capabilityInstalledByTool = [bool](Get-OptionalStateValue -State $previousState -Name 'capabilityInstalledByTool' -DefaultValue ($capabilityBefore.State -ne 'Installed'))

    $serviceBefore = Get-Service -Name sshd -ErrorAction SilentlyContinue
    $serviceConfigBefore = Get-CimInstance -ClassName Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
    $serviceExistedBefore = [bool](Get-OptionalStateValue -State $previousState -Name 'sshServiceExistedBefore' -DefaultValue ($null -ne $serviceBefore))
    $serviceWasRunning = [bool](Get-OptionalStateValue -State $previousState -Name 'sshServiceWasRunning' -DefaultValue (($null -ne $serviceBefore) -and ($serviceBefore.Status.ToString() -eq 'Running')))
    $defaultServiceStartMode = if ($null -ne $serviceConfigBefore) { $serviceConfigBefore.StartMode } else { 'Manual' }
    $servicePreviousStartMode = [string](Get-OptionalStateValue -State $previousState -Name 'sshServicePreviousStartMode' -DefaultValue $defaultServiceStartMode)

    $inboxFirewallRuleName = 'OpenSSH-Server-In-TCP'
    $inboxRuleBefore = Get-NetFirewallRule -Name $inboxFirewallRuleName -ErrorAction SilentlyContinue
    $inboxRuleWasEnabled = [bool](Get-OptionalStateValue -State $previousState -Name 'inboxFirewallRuleWasEnabled' -DefaultValue (($null -ne $inboxRuleBefore) -and ($inboxRuleBefore.Enabled.ToString() -eq 'True')))

    $networkProfileChanged = [bool](Get-OptionalStateValue -State $previousState -Name 'networkProfileChanged' -DefaultValue $false)
    $networkInterfaceIndex = Get-OptionalStateValue -State $previousState -Name 'networkInterfaceIndex' -DefaultValue $null
    $previousNetworkCategory = Get-OptionalStateValue -State $previousState -Name 'previousNetworkCategory' -DefaultValue $null
    $accountCreatedByTool = [bool](Get-OptionalStateValue -State $previousState -Name 'accountCreatedByTool' -DefaultValue $false)
    $installedAtUtc = [string](Get-OptionalStateValue -State $previousState -Name 'installedAtUtc' -DefaultValue ([DateTime]::UtcNow.ToString('o')))
    $account = Get-LocalUser -Name $script:WindowsDevNodeAccountName -ErrorAction SilentlyContinue
    if ($null -ne $account -and ($account.Description -ne $script:WindowsDevNodeAccountDescription -or -not $accountCreatedByTool)) {
        throw "A non-project local account named '$($script:WindowsDevNodeAccountName)' already exists. The installer will not take it over."
    }

    $state = [pscustomobject][ordered]@{
        schemaVersion = 1
        projectVersion = $script:WindowsDevNodeVersion
        accountName = $script:WindowsDevNodeAccountName
        accountCreatedByTool = $accountCreatedByTool
        capabilityInstalledByTool = $capabilityInstalledByTool
        inboxFirewallRuleWasEnabled = $inboxRuleWasEnabled
        networkProfileChanged = $networkProfileChanged
        networkInterfaceIndex = $networkInterfaceIndex
        previousNetworkCategory = $previousNetworkCategory
        sshServiceExistedBefore = $serviceExistedBefore
        sshServiceWasRunning = $serviceWasRunning
        sshServicePreviousStartMode = $servicePreviousStartMode
        authorizedKeysPath = [string](Get-OptionalStateValue -State $previousState -Name 'authorizedKeysPath' -DefaultValue '')
        installedAtUtc = $installedAtUtc
        lastRepairedAtUtc = [DateTime]::UtcNow.ToString('o')
    }

    New-Item -ItemType Directory -Path $paths.StateRoot -Force | Out-Null
    & icacls.exe $paths.StateRoot /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    Assert-LastNativeCommand -Operation 'Securing the managed state directory'
    Save-WindowsDevNodeInstallState -Path $paths.State -State $state

    Write-Output '[INSTALL 2/7] Ensuring Windows OpenSSH Server is installed...'
    if ($capabilityBefore.State -ne 'Installed') {
        Add-WindowsCapability -Online -Name $capabilityName | Out-Null
    }

    Write-Output '[INSTALL 3/7] Configuring the Private LAN and firewall scope...'
    $inboxRule = Get-NetFirewallRule -Name $inboxFirewallRuleName -ErrorAction SilentlyContinue
    if ($null -ne $inboxRule) {
        Disable-NetFirewallRule -Name $inboxFirewallRuleName
    }

    $defaultRoute = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -ne '0.0.0.0' } |
        Sort-Object -Property RouteMetric |
        Select-Object -First 1
    if ($null -eq $defaultRoute) {
        throw 'No active IPv4 default route was found.'
    }

    $activeProfile = Get-NetConnectionProfile -InterfaceIndex $defaultRoute.InterfaceIndex -ErrorAction Stop
    if ($activeProfile.NetworkCategory.ToString() -eq 'Public' -and -not $DoNotChangeNetworkProfile) {
        if (-not $networkProfileChanged) {
            $networkProfileChanged = $true
            $networkInterfaceIndex = $activeProfile.InterfaceIndex
            $previousNetworkCategory = $activeProfile.NetworkCategory.ToString()
            $state.networkProfileChanged = $networkProfileChanged
            $state.networkInterfaceIndex = $networkInterfaceIndex
            $state.previousNetworkCategory = $previousNetworkCategory
            Save-WindowsDevNodeInstallState -Path $paths.State -State $state
        }
        elseif ($null -eq $networkInterfaceIndex -or [int]$networkInterfaceIndex -ne [int]$activeProfile.InterfaceIndex) {
            throw 'A different Public network interface is active. Refusing to change an interface that is not recorded in managed state.'
        }
        Set-NetConnectionProfile -InterfaceIndex $activeProfile.InterfaceIndex -NetworkCategory Private
        $activeProfile = Get-NetConnectionProfile -InterfaceIndex $activeProfile.InterfaceIndex
    }

    if ($activeProfile.NetworkCategory.ToString() -ne 'Private') {
        throw 'The active network is not Private. Rerun without -DoNotChangeNetworkProfile or set the Ethernet profile to Private.'
    }

    $managedRule = Get-NetFirewallRule -Name $script:WindowsDevNodeFirewallRuleName -ErrorAction SilentlyContinue
    if ($null -ne $managedRule) {
        Remove-NetFirewallRule -Name $script:WindowsDevNodeFirewallRuleName
    }
    New-NetFirewallRule -Name $script:WindowsDevNodeFirewallRuleName `
        -DisplayName 'Windows Dev Node SSH (Private LAN only)' `
        -Description 'Managed by windows-dev-node-bootstrap.' `
        -Enabled True `
        -Direction Inbound `
        -Profile Private `
        -Action Allow `
        -Protocol TCP `
        -LocalPort 22 `
        -RemoteAddress LocalSubnet | Out-Null

    Write-Output '[INSTALL 4/7] Configuring the SSH service and standard account...'
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    if ($null -eq $account) {
        if (-not $accountCreatedByTool) {
            $accountCreatedByTool = $true
            $state.accountCreatedByTool = $true
            Save-WindowsDevNodeInstallState -Path $paths.State -State $state
        }
        $randomBytes = New-Object byte[] 48
        $random = [Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $random.GetBytes($randomBytes)
        }
        finally {
            $random.Dispose()
        }
        $generatedPassword = [Convert]::ToBase64String($randomBytes) + '!aA1'
        $securePassword = ConvertTo-SecureString -String $generatedPassword -AsPlainText -Force
        New-LocalUser -Name $script:WindowsDevNodeAccountName `
            -Password $securePassword `
            -Description $script:WindowsDevNodeAccountDescription `
            -AccountNeverExpires `
            -PasswordNeverExpires `
            -UserMayNotChangePassword | Out-Null
        [Array]::Clear($randomBytes, 0, $randomBytes.Length)
        $generatedPassword = $null
        $securePassword = $null
        $account = Get-LocalUser -Name $script:WindowsDevNodeAccountName
    }
    else {
        Enable-LocalUser -Name $script:WindowsDevNodeAccountName
    }

    & net.exe user $script:WindowsDevNodeAccountName '/passwordreq:yes' | Out-Null
    Assert-LastNativeCommand -Operation 'Requiring a password on the managed local account'

    $administrators = Get-LocalGroup -SID 'S-1-5-32-544'
    $administratorMember = Get-LocalGroupMember -Group $administrators.Name -ErrorAction SilentlyContinue |
        Where-Object { $_.SID.Value -eq $account.SID.Value }
    if ($null -ne $administratorMember) {
        Remove-LocalGroupMember -Group $administrators.Name -Member $account.Name
    }

    Write-Output '[INSTALL 5/7] Installing the dedicated SSH public key...'
    $accountSid = $account.SID.Value
    $accountOwner = $account.SID.Translate([Security.Principal.NTAccount]).Value
    $userKeyPaths = Get-WindowsDevNodeUserKeyPaths -User $account
    $profileDirectoryCreated = -not (Test-Path -LiteralPath $userKeyPaths.Profile -PathType Container)
    if ((Test-Path -LiteralPath $userKeyPaths.Profile) -and
        ((Get-Item -LiteralPath $userKeyPaths.Profile -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The managed account profile path is a reparse point and will not be modified.'
    }
    if ($profileDirectoryCreated) {
        New-Item -ItemType Directory -Path $userKeyPaths.Profile -Force | Out-Null
        & icacls.exe $userKeyPaths.Profile /grant:r "*$($accountSid):(OI)(CI)F" | Out-Null
        Assert-LastNativeCommand -Operation 'Granting the managed account access to its profile directory'
        & icacls.exe $userKeyPaths.Profile /setowner $accountOwner | Out-Null
        Assert-LastNativeCommand -Operation 'Setting the managed account profile owner'
    }
    if ((Test-Path -LiteralPath $userKeyPaths.SshDirectory) -and
        ((Get-Item -LiteralPath $userKeyPaths.SshDirectory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The managed account .ssh path is a reparse point and will not be modified.'
    }
    if (Test-Path -LiteralPath $userKeyPaths.AuthorizedKeys -PathType Leaf) {
        $existingUserKey = (Get-Content -LiteralPath $userKeyPaths.AuthorizedKeys -Raw).Trim()
        if ($existingUserKey -cne $publicKey) {
            throw 'The managed account already has a different authorized_keys file. The installer will not overwrite it.'
        }
    }

    New-Item -ItemType Directory -Path $userKeyPaths.SshDirectory -Force | Out-Null
    & icacls.exe $userKeyPaths.SshDirectory /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "*$($accountSid):(OI)(CI)F" | Out-Null
    Assert-LastNativeCommand -Operation 'Securing the managed account .ssh directory'
    & icacls.exe $userKeyPaths.SshDirectory /setowner $accountOwner | Out-Null
    Assert-LastNativeCommand -Operation 'Setting the managed account .ssh owner'

    Write-WindowsDevNodeUtf8NoBom -Path $userKeyPaths.AuthorizedKeys -Content ($publicKey + [Environment]::NewLine)
    & icacls.exe $userKeyPaths.AuthorizedKeys /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' "*$($accountSid):F" | Out-Null
    Assert-LastNativeCommand -Operation 'Securing the managed account authorized_keys file'
    & icacls.exe $userKeyPaths.AuthorizedKeys /setowner $accountOwner | Out-Null
    Assert-LastNativeCommand -Operation 'Setting the managed account authorized_keys owner'

    $state.authorizedKeysPath = $userKeyPaths.AuthorizedKeys
    Save-WindowsDevNodeInstallState -Path $paths.State -State $state

    Write-Output '[INSTALL 6/7] Applying and validating key-only SSH configuration...'
    if (-not (Test-Path -LiteralPath $paths.SshConfig -PathType Leaf)) {
        Restart-Service -Name sshd
    }
    if (-not (Test-Path -LiteralPath $paths.SshConfig -PathType Leaf)) {
        throw 'Windows OpenSSH did not create sshd_config.'
    }

    if (-not (Test-Path -LiteralPath $paths.SshConfigBackup -PathType Leaf)) {
        Copy-Item -LiteralPath $paths.SshConfig -Destination $paths.SshConfigBackup
    }

    if (-not (Test-Path -LiteralPath $paths.SshExecutable -PathType Leaf)) {
        throw 'sshd.exe is missing after OpenSSH installation.'
    }

    $currentConfig = Get-Content -LiteralPath $paths.SshConfig -Raw
    $managedConfig = Set-WindowsDevNodeManagedBlock -Content $currentConfig -AccountName $script:WindowsDevNodeAccountName
    $candidateConfig = Join-Path $paths.StateRoot 'sshd_config.candidate'
    try {
        Write-WindowsDevNodeUtf8NoBom -Path $candidateConfig -Content $managedConfig
        $validationOutput = & $paths.SshExecutable -t -f $candidateConfig 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "sshd_config validation failed: $($validationOutput -join ' ')"
        }
        Write-WindowsDevNodeUtf8NoBom -Path $paths.SshConfig -Content $managedConfig
    }
    finally {
        Remove-Item -LiteralPath $candidateConfig -Force -ErrorAction SilentlyContinue
    }

    Restart-Service -Name sshd
    $listening = $null
    for ($attempt = 0; $attempt -lt 20 -and $null -eq $listening; $attempt++) {
        Start-Sleep -Milliseconds 250
        $listening = Get-NetTCPConnection -State Listen -LocalPort 22 -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $paths.LegacyAuthorizedKeys -PathType Leaf) {
        $legacyKey = (Get-Content -LiteralPath $paths.LegacyAuthorizedKeys -Raw).Trim()
        if ($legacyKey -cne $publicKey) {
            throw 'The legacy ProgramData authorized_keys file was modified and was not removed.'
        }
        Remove-Item -LiteralPath $paths.LegacyAuthorizedKeys -Force
    }

    Save-WindowsDevNodeInstallState -Path $paths.State -State $state

    Write-Output '[INSTALL 7/7] Verifying final readiness...'
    $report = Get-WindowsDevNodeSafeReport
    Write-WindowsDevNodePairingReport -Report $report
    if ($report.status -ne 'READY') {
        exit 2
    }
    exit 0
}
catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
    try {
        $failureReport = Get-WindowsDevNodeSafeReport
        Write-WindowsDevNodePairingReport -Report $failureReport
    }
    catch {
        Write-Error 'A safe diagnostic report could not be produced.'
    }
    exit 1
}
