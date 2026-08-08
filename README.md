# Windows Dev Node Bootstrap

Turn one owned Windows 11 PC into a headless, LAN-only development node with one UAC confirmation. The first release establishes a safe SSH control plane; GUI/RDP setup comes only after the real machine passes the SSH smoke.

## One-command install

Open PowerShell, paste this command, and approve Windows UAC:

```powershell
Write-Host '[START] Downloading bootstrap...'; irm 'https://raw.githubusercontent.com/ChaosRealmsAI/windows-dev-node-bootstrap/main/bootstrap.ps1' -TimeoutSec 60 | iex
```

The current window immediately shows download/extraction progress. The Administrator window then stays open and prints seven installation steps followed by the pairing report or an actionable error.

## What it does

- Installs the built-in Windows OpenSSH Server capability when needed.
- Creates the dedicated standard local account `codexdev` with a generated password that is never printed or stored.
- Installs only the public half of a dedicated SSH key and requires public-key authentication for `codexdev`.
- Starts `sshd` automatically after reboot.
- Allows TCP 22 only from `LocalSubnet` on a Private Windows network profile.
- Changes the active route's network profile from Public to Private when necessary, records that change, and restores it on uninstall.
- Prints a sanitized `PAIRING REPORT` without addresses, credentials, device identifiers, or host fingerprints.
- Supports idempotent repair, read-only diagnosis, and scoped uninstall.

It does **not** configure public internet access, router port forwarding, administrator SSH, RDP, WSL2, automatic sign-in, or third-party remote-control software.

Run it only while the Windows PC is connected to a LAN you trust; setting a network to Private enables Windows' trusted-network behavior beyond this project's SSH rule.

## Option A: Git clone

Open PowerShell on Windows:

```powershell
git clone https://github.com/ChaosRealmsAI/windows-dev-node-bootstrap.git
cd .\windows-dev-node-bootstrap
.\install.cmd
```

## Option B: GitHub ZIP

1. [Download the current ZIP](https://github.com/ChaosRealmsAI/windows-dev-node-bootstrap/archive/refs/heads/main.zip).
2. Extract the ZIP completely.
3. Open `windows-dev-node-bootstrap` and double-click `install.cmd`.
4. Approve the single Windows UAC prompt.

The installer invokes the checked-in PowerShell file with a process-scoped execution-policy override because files extracted from a downloaded ZIP can carry Windows Mark-of-the-Web. Review the scripts or pin the Git commit before running them.

## What to send back

Wait for the final block:

```text
=== WINDOWS DEV NODE PAIRING REPORT BEGIN ===
{ ... sanitized JSON ... }
=== WINDOWS DEV NODE PAIRING REPORT END ===
```

Copy only that block into the Codex conversation. Do not send the complete terminal history, passwords, product keys, account emails, IP addresses, or screenshots of unrelated Windows content.

When `status` is `READY`, the controller can rediscover TCP 22 on the private LAN and perform the first key-authenticated SSH smoke. The private key stays on the controller and is never committed.

## Diagnose or repair

```powershell
# Read-only readiness report (UAC protects access to managed state)
.\diagnose.cmd

# Safe, repeatable repair
.\install.cmd
```

## Remove access

```powershell
.\uninstall.cmd
```

Type `REMOVE` when prompted. Uninstall removes the project-owned account, key, firewall rule, state, and marked SSH configuration block. It intentionally leaves the Windows OpenSSH capability installed so unrelated users or configuration are not damaged.

## Validation

```bash
python3 tests/static_contract.py
pwsh -NoProfile -File tests/Validate-Project.ps1
powershell.exe -NoProfile -File tests/Validate-Project.ps1
```

The GitHub workflow runs both checks. Final acceptance still requires the first owned Windows machine to pass installation, report inspection, LAN SSH login, file transfer, reboot, and monitor-disconnected replay.

## Security references

- [Get started with OpenSSH Server for Windows](https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse)
- [Key-based authentication in OpenSSH for Windows](https://learn.microsoft.com/windows-server/administration/openssh/openssh_keymanagement)
- [OpenSSH Server configuration for Windows](https://learn.microsoft.com/windows-server/administration/openssh/openssh-server-configuration)

## License

[MIT](LICENSE)
