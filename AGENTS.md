# Windows Dev Node Bootstrap

This project turns one owned Windows 11 machine into a LAN-only development node that can be reached with a dedicated SSH key.

## Boundaries

- `install.cmd`, `diagnose.cmd`, and `uninstall.cmd` are the stable user entry points.
- Windows implementation scripts live under `scripts/windows/`; validation scripts live under `tests/`.
- Never commit a private key, password, token, device address, MAC address, serial number, or raw machine report.
- The managed account stays a standard local user. Administrator access, RDP, WSL, public-network exposure, and third-party remote-control software are outside v0.1.
- The installer may manage only the `codexdev` account, `WindowsDevNode-SSH-In-TCP` firewall rule, the marked `sshd_config` block, and `%ProgramData%\WindowsDevNode`.
- Repeated installation must be idempotent. Uninstall must not remove OpenSSH or overwrite unrelated SSH configuration.

## Commands

```bash
# Portable static contract
python3 tests/static_contract.py

# PowerShell syntax and repository contract (PowerShell 7 or Windows PowerShell)
pwsh -NoProfile -File tests/Validate-Project.ps1
powershell.exe -NoProfile -File tests/Validate-Project.ps1
```

On an owned Windows 11 test machine:

```powershell
# Install/start
.\install.cmd

# Inspect current readiness
.\diagnose.cmd

# Stop access and remove project-owned resources
.\uninstall.cmd
```

## Acceptance

1. `install.cmd` requests one normal UAC confirmation and ends with a delimited `PAIRING REPORT` whose status is `READY`.
2. Only TCP 22 from `LocalSubnet` on a Private network profile reaches `sshd`.
3. `codexdev` is enabled, is not an administrator, and accepts the committed public key while rejecting password authentication.
4. After a Windows reboot with the monitor disconnected, SSH key login, command execution, and file transfer still work.
5. `uninstall.cmd` removes only project-owned access and leaves unrelated OpenSSH installation/configuration intact.
