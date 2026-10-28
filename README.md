# PSNutanixOps

Unofficial PowerShell tooling for Nutanix Prism Central v4 API

[![Build Status](https://img.shields.io/github/actions/workflow/status/mcruise40/PSNutanixOps/ci.yml?branch=main&logo=github&style=flat-square)](https://github.com/mcruise40/PSNutanixOps/actions/workflows/ci.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/PSNutanixOps.svg)](https://www.powershellgallery.com/packages/PSNutanixOps)
[![Downloads](https://img.shields.io/powershellgallery/dt/PSNutanixOps.svg)](https://www.powershellgallery.com/packages/PSNutanixOps)
[![License](https://img.shields.io/github/license/mcruise40/PSNutanixOps)](LICENSE)

## About

PSNutanixOps is a PowerShell module for day-to-day operations of Nutanix AHV environments through the Prism Central v4 REST API: VM inventory, performance checks (CPU Ready, CPU peak with N-1 projection), recovery point management and a pre-upgrade readiness check with an HTML report for the change.

It replaces the standalone scripts of [nutanix-ps-scripts](https://github.com/mcruise40/nutanix-ps-scripts). Each script carried its own copy of the API, paging and lookup code; the module shares one tested implementation.

> **Not affiliated with Nutanix.** The official Nutanix modules are `Nutanix.Cli`, `Nutanix.Prism.Common` and `Nutanix.Prism.PS.Cmds`. PSNutanixOps uses its own command prefix `Nxo` so it can be loaded next to them without name clashes (the legacy Nutanix cmdlets use `NTNX`, and PowerShell command names are case-insensitive).

## 🚀 Getting Started

### Prerequisites

- **PowerShell 7.0+** (Windows, Linux, macOS)
- A Prism Central login that can read the objects you query (and change them for the recovery point commands)

### Installation

```powershell
Install-Module -Name PSNutanixOps -Scope CurrentUser
```

### Connect

```powershell
$cred = Get-Credential
Connect-NxoPrismCentral -Server pc01.example.local -Credential $cred -SkipCertificateCheck
```

Connect once; every command then works on all connected Prism Central instances, or on the ones named with `-Server`. Use `-SkipCertificateCheck` when Prism Central uses a self-signed certificate - certificates are validated by default.

### Examples

```powershell
# VM asset inventory as CSV
Get-NxoVmInventory | Export-Csv .\VM-Inventory.csv -Delimiter ';' -NoTypeInformation -Encoding utf8

# VMs without NGT or with an outdated NGT version
Get-NxoVmInventory | Where-Object { -not $_.NGT_Installed -or $_.NGT_UpdateNeeded }

# CPU peak per cluster and host, projected onto N-1 hosts
Get-NxoClusterCpuPeak -ClusterName NTNX-CL01 | Format-Table

# Pre-upgrade check with HTML report for the change
Test-NxoUpgradeReadiness -ClusterName NTNX-CL01 -ChangeId CHG0012345

# Recovery points before patching, cleanup afterwards
New-NxoRecoveryPoint -CategoryKey Patching -CategoryValue Group1 -RecoveryPointName PrePatch -RetentionDays 3
Get-NxoRecoveryPoint -CategoryKey Patching -CategoryValue Group1 | Where-Object Name -eq 'PrePatch' | Remove-NxoRecoveryPoint
```

More in the [usage guide](docs/getting-started.md).

## Commands

| Command | Purpose |
|---|---|
| `Connect-NxoPrismCentral` | Checks the login and stores the connection for the session |
| `Disconnect-NxoPrismCentral` | Removes stored connections |
| `Get-NxoConnection` | Lists the connections of the session |
| `Get-NxoVmInventory` | VM asset inventory: sizing, guest OS, NGT, boot/vTPM, network, protection, categories, placement |
| `Get-NxoVmCpuReady` | CPU Ready per VM (summary or samples) |
| `Get-NxoClusterCpuPeak` | CPU peak per cluster and host with N-1 projection |
| `Get-NxoRecoveryPoint` | Lists recovery points, filtered by VM name or category |
| `New-NxoRecoveryPoint` | Creates on-demand recovery points, one per VM |
| `Remove-NxoRecoveryPoint` | Deletes recovery points (asks per recovery point) |
| `Invoke-NxoRecoveryPointCleanup` | Guided cleanup of expired or orphaned recovery points |
| `Test-NxoUpgradeReadiness` | Pre-upgrade readiness check with HTML report |

`Get-Help <command> -Full` shows parameters, examples and notes.

## Migration from nutanix-ps-scripts

| Script | Command |
|---|---|
| `Inventory/Get-NtnxVmInventory.ps1` | `Get-NxoVmInventory` |
| `Performance/Get-NtnxVmCpuReady.ps1` | `Get-NxoVmCpuReady` |
| `Performance/Get-NtnxClusterCpuPeak.ps1` | `Get-NxoClusterCpuPeak` |
| `RecoveryPoints/Get-NtnxRecoveryPoints.ps1` | `Get-NxoRecoveryPoint` |
| `RecoveryPoints/New-NtnxGroupRecoveryPoint.ps1` | `New-NxoRecoveryPoint` |
| `RecoveryPoints/Remove-NtnxRecoveryPoint.ps1` | `Remove-NxoRecoveryPoint` |
| `RecoveryPoints/Invoke-NtnxRecoveryPointCleanup.ps1` | `Invoke-NxoRecoveryPointCleanup` |
| `Upgrade/Test-NtnxUpgradeReadiness.ps1` | `Test-NxoUpgradeReadiness` |

The `Move/` scripts run inside the guest and stay in nutanix-ps-scripts.

What changed:

- **Connection:** `-PcIp` / `-Credential` per script are replaced by `Connect-NxoPrismCentral`. All commands accept `-Server` to limit them to some of the connected instances.
- **Certificates:** validated by default; use `Connect-NxoPrismCentral -SkipCertificateCheck` for self-signed certificates (the scripts always skipped the check).
- **API revision:** negotiated per namespace. The preferred revision (`-ApiVersion` on connect, default `v4.2`) is tried first, then v4.3 down to v4.0; the first one that works is remembered.
- **CSV export:** the `-CsvPath` parameters are gone; pipe to `Export-Csv` instead.
- **Parameter names:** singular (`-VmName`, `-ClusterName`, `-NccReportRecipient`); the old plural names still work as aliases. `-VmName` accepts wildcards everywhere.
- **Pipelines:** `Get-NxoRecoveryPoint | Remove-NxoRecoveryPoint` and `Get-NxoVmInventory | New-NxoRecoveryPoint` work directly. Recovery point and check results are returned as objects.
- **Output streams:** status messages of the non-interactive commands go to the verbose stream (`-Verbose`). The interactive commands (`Test-NxoUpgradeReadiness`, `Invoke-NxoRecoveryPointCleanup`) still write to the console.
- **Rate limits:** every command retries automatically when Prism Central reports its API rate limit (HTTP 429).

## 📘 Documentation

- 🚀 **[Usage guide](docs/getting-started.md)** - workflows, pipelines and troubleshooting
- 🛠️ **[Development](docs/development.md)** and **[CI/CD](docs/ci-cd.md)** - build, test and release

## 🤝 Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the pull request workflow, code style and testing requirements.

---

Built by [mcruise40](https://github.com/mcruise40)
