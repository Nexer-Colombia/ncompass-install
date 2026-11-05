# Nexer Compass installer

Nexer Compass is Nexer's distribution of [Gentle AI](https://github.com/Gentleman-Programming/gentle-ai) for Claude Code. It sets up Claude Code with Nexer's approved workflow, plugins and tools, and keeps them up to date.

This repository holds only what people need to install it:

- **`install.ps1`**: the one-time install script for Windows.
- **Releases**: the `ncompass.exe` program for each channel, with its checksum.

The source code is kept in a separate repository.

> **For Nexer employees.** Compass is set up for Nexer's Claude organization. Outside Nexer it won't be useful.

## Requirements

- Windows 10 or 11 (x64)
- Windows PowerShell 5.1 or later
- [Claude Code](https://code.claude.com), signed in with your Nexer Claude account

You don't need a GitHub account.

## Install

<!-- TODO (NESS-42): replace with the final command once install.ps1 is published. -->

Open **Windows PowerShell** (not as administrator) and run:

```powershell
irm https://raw.githubusercontent.com/Nexer-Colombia/ncompass-install/main/install.ps1 | iex
```

When it finishes, open a new terminal and run:

```powershell
ncompass about
```

Compass updates itself after that. You don't need to run the installer again.

## Channels

| Channel | GitHub release type | Who it's for |
|---|---|---|
| **stable** | normal release, marked *Latest* | everyone (the default) |
| **early** | pre-release | volunteers who try new versions first |

Every version is released to **early** first. After a maintainer approves it, the **same file** is promoted to **stable**, so stable is always exactly what early tested.

## Each release contains

| File | What it is |
|---|---|
| `ncompass.exe` | the Compass program for Windows x64 |
| `ncompass.exe.sha256` | its SHA-256 checksum |
| `LICENSE-gentle-ai.txt` | Gentle AI's MIT license notice |

The installer and the self-update refuse a download whose checksum doesn't match.

### Check a download by hand

```powershell
$expected = (Get-Content .\ncompass.exe.sha256).Split(' ')[0]
$actual   = (Get-FileHash .\ncompass.exe -Algorithm SHA256).Hash
if ($actual -eq $expected) { 'OK: checksum matches' } else { 'STOP: checksum does not match' }
```

## Third-party notices

Compass is built on [Gentle AI](https://github.com/Gentleman-Programming/gentle-ai), which is released under the MIT License. Its license notice is included in every release as `LICENSE-gentle-ai.txt`.

## Help and security

- **Problems or questions:** <!-- TODO: Nexer channel or contact, e.g. #nexer-compass on Slack/Teams --> Please don't open public issues with internal details.
- **Security issues:** report them privately to <!-- TODO: security contact -->, not in a public issue.
