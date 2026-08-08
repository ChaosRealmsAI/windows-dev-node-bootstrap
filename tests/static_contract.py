#!/usr/bin/env python3
"""Purpose: Validate the portable repository and security contract.

Usage: python3 tests/static_contract.py
Notes: This check never executes the Windows installer or reads machine state.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise AssertionError(message)


def read(relative_path: str) -> str:
    path = PROJECT_ROOT / relative_path
    if not path.is_file():
        fail(f"missing required file: {relative_path}")
    return path.read_text(encoding="utf-8")


def main() -> int:
    required_files = (
        "AGENTS.md",
        "LICENSE",
        "README.md",
        "bootstrap.ps1",
        "install.cmd",
        "diagnose.cmd",
        "uninstall.cmd",
        "config/codex_authorized_key.pub",
        "privacy/spec/README.md",
        "privacy/spec/spec-map.md",
        "scripts/windows/Common.ps1",
        "scripts/windows/Install-WindowsDevNode.ps1",
        "scripts/windows/Get-WindowsDevNodeReport.ps1",
        "scripts/windows/Uninstall-WindowsDevNode.ps1",
        "tests/Validate-Project.ps1",
        ".github/workflows/validate.yml",
    )
    for relative_path in required_files:
        read(relative_path)

    public_key = read("config/codex_authorized_key.pub").strip()
    if "\n" in public_key or not re.fullmatch(
        r"ssh-(?:ed25519|rsa|ecdsa-[^ ]+) [A-Za-z0-9+/=]+(?: [^\r\n]+)?",
        public_key,
    ):
        fail("public key must be one valid OpenSSH public-key line")

    ignored_scan_parts = {".git", ".tmp", "artifacts", "__pycache__"}
    this_test = Path(__file__).resolve()
    tracked_text = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in PROJECT_ROOT.rglob("*")
        if path.is_file()
        and path.resolve() != this_test
        and not ignored_scan_parts.intersection(path.parts)
    )
    private_markers = tuple(
        "BEGIN " + key_kind + " PRIVATE KEY"
        for key_kind in ("OPENSSH", "RSA", "EC")
    ) + ("PRIVATE KEY" + "-----",)
    for marker in private_markers:
        if marker in tracked_text:
            fail(f"private-key material marker found: {marker}")

    common = read("scripts/windows/Common.ps1")
    bootstrap = read("bootstrap.ps1")
    readme = read("README.md")
    installer = read("scripts/windows/Install-WindowsDevNode.ps1")
    uninstaller = read("scripts/windows/Uninstall-WindowsDevNode.ps1")
    install_launcher = read("install.cmd")
    diagnose_launcher = read("diagnose.cmd")
    uninstall_launcher = read("uninstall.cmd")
    specification = read("privacy/spec/README.md")

    required_contract_fragments = (
        "WindowsDevNode-SSH-In-TCP",
        "LocalSubnet",
        "AuthenticationMethods publickey",
        "PasswordAuthentication no",
        "codexdev",
        "PAIRING REPORT BEGIN",
        "PAIRING REPORT END",
    )
    contract_text = common + installer + specification
    for fragment in required_contract_fragments:
        if fragment not in contract_text:
            fail(f"missing contract fragment: {fragment}")

    if "-Profile Any" in installer or re.search(
        r"-RemoteAddress\s+['\"]?0\.0\.0\.0/0", installer, flags=re.IGNORECASE
    ):
        fail("installer must not create a broad inbound firewall scope")
    if "Add-LocalGroupMember" in installer and "S-1-5-32-544" in installer:
        fail("installer must never add the managed account to Administrators")
    if "Remove-Item -LiteralPath $paths.StateRoot -Recurse -Force" not in uninstaller:
        fail("uninstaller must use the exact managed state path")
    if "Remove-WindowsCapability" in uninstaller:
        fail("uninstaller must preserve the shared OpenSSH capability")

    for fragment in (
        "windows-dev-node-bootstrap/archive/refs/heads/main.zip",
        "[guid]::NewGuid()",
        "[BOOTSTRAP 1/4]",
        "[BOOTSTRAP 4/4]",
        "-TimeoutSec 60",
        "-NoExit",
        "-Verb RunAs",
        "Start-Process",
    ):
        if fragment not in bootstrap:
            fail(f"bootstrap is missing required fragment: {fragment}")
    if "Remove-Item" in bootstrap:
        fail("bootstrap must not recursively replace or delete a shared temporary path")
    if "[INSTALL 1/7]" not in installer or "[INSTALL 7/7]" not in installer:
        fail("installer must show bounded step-by-step progress")
    if "Write-Host '[START] Downloading bootstrap...'" not in readme:
        fail("README one-line command must show progress before its first network request")
    if "bootstrap.ps1' -TimeoutSec 60 | iex" not in readme:
        fail("README one-line bootstrap request must have a timeout")

    for name, launcher in (
        ("install.cmd", install_launcher),
        ("diagnose.cmd", diagnose_launcher),
        ("uninstall.cmd", uninstall_launcher),
    ):
        if launcher.count("-Verb RunAs") != 1 or "$env:WINDOWS_DEV_NODE_ENTRY" not in launcher:
            fail(f"{name} must use one path-safe UAC relaunch")

    forbidden_report_fields = (
        r"\bhostName\s*=",
        r"\bipAddress\s*=",
        r"\bmacAddress\s*=",
        r"\bserialNumber\s*=",
        r"\bhostKeyFingerprint\s*=",
        r"\bpassword\s*=",
        r"\btoken\s*=",
    )
    for pattern in forbidden_report_fields:
        if re.search(pattern, common, flags=re.IGNORECASE):
            fail(f"unsafe pairing-report field found: {pattern}")

    for path in (PROJECT_ROOT / "scripts").rglob("*"):
        if not path.is_file():
            continue
        head = "\n".join(path.read_text(encoding="utf-8").splitlines()[:5])
        for label in ("Purpose:", "Usage:", "Notes:"):
            if label not in head:
                fail(f"{path.relative_to(PROJECT_ROOT)} lacks top-level {label} comment")

    print("portable contract: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"portable contract: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
