# Windows Dev Node Bootstrap Spec

## Product result

An owner downloads or clones this project on a Windows 11 development machine, runs one stable entry point, approves one UAC prompt, and receives a sanitized readiness report. A trusted controller on the same private LAN can then authenticate as a dedicated standard user with a pre-provisioned SSH public key. No password or private key is exchanged in chat.

## User path

1. The owner clones the repository or extracts its GitHub source ZIP.
2. The owner runs `install.cmd` and confirms Windows UAC.
3. The installer validates its bundled public key, installs the Windows OpenSSH optional capability when absent, creates or reuses only the project-owned `codexdev` standard account, and configures key-only authentication for that account.
4. The installer narrows inbound SSH to `LocalSubnet` on a Private network profile, starts `sshd`, and sets it to Automatic.
5. The installer validates `sshd_config`, verifies the listener and managed resources, then prints only the delimited `PAIRING REPORT`.
6. The owner shares that delimited report. The controller discovers the node on the LAN and performs a first SSH smoke.
7. A reboot and monitor-disconnected SSH smoke prove persistent, headless operation.

## Security invariants

- The repository contains one public key only. The matching private key remains outside the repository with owner-only filesystem permissions.
- The managed Windows account is never added to the local Administrators group.
- The account password is generated with a cryptographic RNG, is never printed or persisted, and cannot be used over SSH because the account-specific SSH rule requires `publickey`.
- The managed firewall rule allows TCP 22 only from `LocalSubnet` and only on a Private profile.
- If the active default route is Public, the installer records its interface and prior category before changing it to Private; uninstall restores only that recorded interface.
- The installer disables the broad in-box OpenSSH firewall rule while this project is active and records enough prior state to restore its enabled/disabled state on uninstall.
- The report excludes host names, IP addresses, MAC addresses, hardware identifiers, SSH host fingerprints, passwords, tokens, and raw logs.
- The project never configures router port forwarding, a public listener, VPN accounts, RDP, administrator SSH, or security bypasses.

## Managed resources

- Local account: `codexdev`, with an exact project ownership description.
- Firewall rule: `WindowsDevNode-SSH-In-TCP`.
- State directory: `%ProgramData%\WindowsDevNode`.
- OpenSSH config: one block delimited by `# BEGIN WindowsDevNode managed block` and `# END WindowsDevNode managed block`.
- Windows optional capability: `OpenSSH.Server~~~~0.0.1.0`; uninstall deliberately preserves the capability.

## Failure and recovery

- Rerunning `install.cmd` repairs project-owned resources and does not create duplicate users, keys, firewall rules, or SSH config blocks.
- An existing non-project `codexdev` account is a hard stop; the installer never takes it over.
- Invalid SSH configuration is detected with `sshd.exe -t` before the service is restarted.
- `diagnose.cmd` can reproduce the sanitized report without reinstalling.
- `uninstall.cmd` requires an explicit local confirmation, removes only resources proven to be project-owned, and preserves OpenSSH for other users.

## Version and non-goals

- Contract version: `0.1.0`.
- Target: an owner-operated Windows 11 machine on a trusted private LAN.
- RDP/GUI control, WSL2, Codex installation, Wake-on-LAN, public internet access, and automatic sign-in are separate follow-up slices after SSH bootstrap is proven on the real machine.
