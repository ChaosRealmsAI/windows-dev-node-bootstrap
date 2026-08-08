# Purpose: Provide shared constants, safe reporting, and config helpers for the Windows dev node.
# Usage: Dot-source this file from another script in scripts/windows.
# Notes: Safe reports deliberately exclude network addresses and machine identifiers.

Set-StrictMode -Version Latest

$script:WindowsDevNodeVersion = '0.1.0'
$script:WindowsDevNodeAccountName = 'codexdev'
$script:WindowsDevNodeAccountDescription = 'Managed by windows-dev-node-bootstrap'
$script:WindowsDevNodeFirewallRuleName = 'WindowsDevNode-SSH-In-TCP'
$script:WindowsDevNodeConfigBegin = '# BEGIN WindowsDevNode managed block'
$script:WindowsDevNodeConfigEnd = '# END WindowsDevNode managed block'
$script:WindowsDevNodeProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Get-WindowsDevNodePaths {
    [CmdletBinding()]
    param()

    $stateRoot = Join-Path $env:ProgramData 'WindowsDevNode'
    [pscustomobject]@{
        ProjectRoot = $script:WindowsDevNodeProjectRoot
        PublicKey = Join-Path $script:WindowsDevNodeProjectRoot 'config\codex_authorized_key.pub'
        StateRoot = $stateRoot
        State = Join-Path $stateRoot 'state.json'
        AuthorizedKeys = Join-Path $stateRoot 'authorized_keys'
        SshConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
        SshConfigBackup = Join-Path $stateRoot 'sshd_config.before-windows-dev-node'
        SshExecutable = Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe'
    }
}

function Assert-WindowsDevNodeAdministrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator rights are required. Run install.cmd or uninstall.cmd and approve the UAC prompt.'
    }
}

function Write-WindowsDevNodeUtf8NoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Get-WindowsDevNodeState {
    [CmdletBinding()]
    param()

    $paths = Get-WindowsDevNodePaths
    if (-not (Test-Path -LiteralPath $paths.State -PathType Leaf)) {
        return $null
    }

    try {
        $state = Get-Content -LiteralPath $paths.State -Raw | ConvertFrom-Json
        $schemaVersion = $state.PSObject.Properties['schemaVersion']
        $accountName = $state.PSObject.Properties['accountName']
        if ($null -eq $schemaVersion -or [int]$schemaVersion.Value -ne 1) {
            throw 'unsupported schemaVersion'
        }
        if ($null -eq $accountName -or [string]$accountName.Value -ne $script:WindowsDevNodeAccountName) {
            throw 'managed account identity does not match this project'
        }
        return $state
    }
    catch {
        throw "The managed state file is invalid: $($_.Exception.Message)"
    }
}

function Remove-WindowsDevNodeManagedBlock {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

    $begin = [regex]::Escape($script:WindowsDevNodeConfigBegin)
    $end = [regex]::Escape($script:WindowsDevNodeConfigEnd)
    $beginCount = [regex]::Matches($Content, $begin).Count
    $endCount = [regex]::Matches($Content, $end).Count
    if ($beginCount -ne $endCount -or $beginCount -gt 1) {
        throw 'The managed sshd_config markers are incomplete or duplicated. Repair them manually before continuing.'
    }

    $pattern = "(?ms)^\s*$begin\s*\r?\n.*?^\s*$end\s*(?:\r?\n)?"
    $withoutManagedBlock = [regex]::Replace($Content, $pattern, '')
    return $withoutManagedBlock.TrimEnd() + [Environment]::NewLine
}

function Set-WindowsDevNodeManagedBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$AccountName
    )

    $base = Remove-WindowsDevNodeManagedBlock -Content $Content
    $block = @(
        $script:WindowsDevNodeConfigBegin
        "Match User $($AccountName.ToLowerInvariant())"
        '    AuthenticationMethods publickey'
        '    PubkeyAuthentication yes'
        '    PasswordAuthentication no'
        '    AuthorizedKeysFile __PROGRAMDATA__/WindowsDevNode/authorized_keys'
        $script:WindowsDevNodeConfigEnd
        ''
    ) -join [Environment]::NewLine

    return $base + [Environment]::NewLine + $block
}

function Test-WindowsDevNodeManagedBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$AccountName
    )

    $lines = @($Content -split '\r?\n')
    $beginIndexes = @(for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -ceq $script:WindowsDevNodeConfigBegin) { $index }
    })
    $endIndexes = @(for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -ceq $script:WindowsDevNodeConfigEnd) { $index }
    })
    if ($beginIndexes.Count -ne 1 -or $endIndexes.Count -ne 1 -or $endIndexes[0] -le $beginIndexes[0]) {
        return $false
    }

    $expectedBlock = @(
        $script:WindowsDevNodeConfigBegin
        "Match User $($AccountName.ToLowerInvariant())"
        '    AuthenticationMethods publickey'
        '    PubkeyAuthentication yes'
        '    PasswordAuthentication no'
        '    AuthorizedKeysFile __PROGRAMDATA__/WindowsDevNode/authorized_keys'
        $script:WindowsDevNodeConfigEnd
    ) -join "`n"
    $actualBlock = $lines[$beginIndexes[0]..$endIndexes[0]] -join "`n"
    return $actualBlock -ceq $expectedBlock
}

function Test-WindowsDevNodeAdministratorMembership {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$User)

    try {
        $administrators = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
        $memberSids = @(Get-LocalGroupMember -Group $administrators.Name -ErrorAction Stop | ForEach-Object { $_.SID.Value })
        return $memberSids -contains $User.SID.Value
    }
    catch {
        return $true
    }
}

function Get-WindowsDevNodeSafeReport {
    [CmdletBinding()]
    param()

    $paths = Get-WindowsDevNodePaths
    $reasons = New-Object System.Collections.Generic.List[string]

    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $service = Get-Service -Name sshd -ErrorAction SilentlyContinue
    $serviceConfig = Get-CimInstance -ClassName Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
    $listener = Get-NetTCPConnection -State Listen -LocalPort 22 -ErrorAction SilentlyContinue
    $user = Get-LocalUser -Name $script:WindowsDevNodeAccountName -ErrorAction SilentlyContinue
    $userIsAdministrator = if ($null -ne $user) { Test-WindowsDevNodeAdministratorMembership -User $user } else { $false }

    $keyConfigured = $false
    if ((Test-Path -LiteralPath $paths.AuthorizedKeys -PathType Leaf) -and (Test-Path -LiteralPath $paths.PublicKey -PathType Leaf)) {
        $keyText = (Get-Content -LiteralPath $paths.AuthorizedKeys -Raw).Trim()
        $expectedKeyText = (Get-Content -LiteralPath $paths.PublicKey -Raw).Trim()
        $keyConfigured = $keyText -ceq $expectedKeyText
    }

    $configManaged = $false
    if (Test-Path -LiteralPath $paths.SshConfig -PathType Leaf) {
        $configText = Get-Content -LiteralPath $paths.SshConfig -Raw
        $configManaged = Test-WindowsDevNodeManagedBlock -Content $configText -AccountName $script:WindowsDevNodeAccountName
    }

    $firewallRules = @(Get-NetFirewallRule -Name $script:WindowsDevNodeFirewallRuleName -ErrorAction SilentlyContinue)
    $firewallScoped = $false
    if ($firewallRules.Count -eq 1) {
        $firewallRule = $firewallRules[0]
        $addressFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $firewallRule -ErrorAction SilentlyContinue
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $firewallRule -ErrorAction SilentlyContinue
        $remoteAddresses = @($addressFilter | ForEach-Object { $_.RemoteAddress })
        $profileNames = @($firewallRule.Profile.ToString().Split(',') | ForEach-Object { $_.Trim() })
        $firewallScoped = ($firewallRule.Enabled.ToString() -eq 'True') -and
            ($firewallRule.Direction.ToString() -eq 'Inbound') -and
            ($firewallRule.Action.ToString() -eq 'Allow') -and
            ($profileNames.Count -eq 1) -and ($profileNames[0] -eq 'Private') -and
            ($remoteAddresses.Count -eq 1) -and ($remoteAddresses[0] -eq 'LocalSubnet') -and
            ($null -ne $portFilter) -and
            ($portFilter.Protocol.ToString() -in @('TCP', '6')) -and
            ($portFilter.LocalPort.ToString() -eq '22')
    }
    $inboxFirewallRules = @(Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)
    $inboxFirewallRuleDisabled = $inboxFirewallRules.Count -eq 0 -or @(
        $inboxFirewallRules | Where-Object { $_.Enabled.ToString() -ne 'False' }
    ).Count -eq 0

    $activeNetworkCategories = @(
        Get-NetConnectionProfile -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4Connectivity.ToString() -ne 'Disconnected' } |
            ForEach-Object { $_.NetworkCategory.ToString() } |
            Sort-Object -Unique
    )
    $networkIsTrusted = $activeNetworkCategories -contains 'Private'

    if ($null -eq $service -or $service.Status.ToString() -ne 'Running') { $reasons.Add('sshd service is not running') }
    if ($null -eq $serviceConfig -or $serviceConfig.StartMode -ne 'Auto') { $reasons.Add('sshd service startup is not Automatic') }
    if ($null -eq $listener) { $reasons.Add('TCP 22 is not listening') }
    if ($null -eq $user -or -not $user.Enabled) { $reasons.Add('managed account is missing or disabled') }
    if ($userIsAdministrator) { $reasons.Add('managed account has administrator membership') }
    if (-not $keyConfigured) { $reasons.Add('authorized public key is missing or invalid') }
    if (-not $configManaged) { $reasons.Add('managed sshd configuration is missing') }
    if (-not $firewallScoped) { $reasons.Add('managed firewall rule is not Private and LocalSubnet only') }
    if (-not $inboxFirewallRuleDisabled) { $reasons.Add('the broad in-box OpenSSH firewall rule is enabled') }
    if (-not $networkIsTrusted) { $reasons.Add('no active Private network profile was found') }

    $status = if ($reasons.Count -eq 0) { 'READY' } else { 'BLOCKED' }
    $startMode = if ($null -ne $serviceConfig) { $serviceConfig.StartMode } else { 'Missing' }
    $serviceStatus = if ($null -ne $service) { $service.Status.ToString() } else { 'Missing' }
    $edition = if ($null -ne $operatingSystem) { $operatingSystem.Caption } else { 'Unknown Windows edition' }
    $architecture = if ($null -ne $operatingSystem) { $operatingSystem.OSArchitecture } else { 'Unknown' }

    [pscustomobject][ordered]@{
        schemaVersion = 1
        projectVersion = $script:WindowsDevNodeVersion
        status = $status
        nodeAlias = 'windows-dev-node'
        osEdition = $edition
        architecture = $architecture
        managedAccount = $script:WindowsDevNodeAccountName
        accountPrivilege = if ($null -eq $user) { 'missing' } elseif ($userIsAdministrator) { 'unexpected-administrator' } else { 'standard-user' }
        authentication = if ($keyConfigured -and $configManaged) { 'publickey-only-for-managed-account' } else { 'not-ready' }
        sshService = $serviceStatus
        sshStartup = $startMode
        sshPort = 22
        sshListening = ($null -ne $listener)
        firewallScope = if ($firewallScoped) { 'Private/LocalSubnet' } else { 'not-ready' }
        activeNetworkCategories = [string[]]$activeNetworkCategories
        blockers = [string[]]$reasons.ToArray()
        checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Write-WindowsDevNodePairingReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Report)

    Write-Output '=== WINDOWS DEV NODE PAIRING REPORT BEGIN ==='
    Write-Output ($Report | ConvertTo-Json -Depth 4)
    Write-Output '=== WINDOWS DEV NODE PAIRING REPORT END ==='
}
