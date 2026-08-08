# Purpose: Produce the sanitized Windows development node readiness report.
# Usage: Run from diagnose.cmd or from an existing PowerShell session.
# Notes: Output excludes addresses, host keys, credentials, and machine identifiers.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

try {
    Assert-WindowsDevNodeAdministrator
    $report = Get-WindowsDevNodeSafeReport
    Write-WindowsDevNodePairingReport -Report $report
    if ($report.status -ne 'READY') {
        exit 2
    }
}
catch {
    Write-Error "Unable to create the safe report: $($_.Exception.Message)"
    exit 1
}
