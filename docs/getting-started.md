# PSNutanixOps Usage Guide

## Overview

PSNutanixOps works with the Nutanix Prism Central v4 REST API. You connect once per PowerShell session; all commands then work on the connected Prism Central instances. Every cluster registered to a Prism Central is covered, and most commands can be limited with `-ClusterName`.

## Key Features

- One connection per session, any number of Prism Central instances
- API revision negotiated per namespace (v4.0 to v4.3), so the same command works on older and newer Prism Central releases
- Objects as output: filter, sort and export them with the usual PowerShell commands
- Automatic retry when Prism Central reports its API rate limit
- Interactive pre-upgrade check and recovery point cleanup that leave an audit trail (HTML report, log, results CSV)

## Core Functions

| Area | Commands |
|---|---|
| Connection | `Connect-NxoPrismCentral`, `Disconnect-NxoPrismCentral`, `Get-NxoConnection` |
| Inventory | `Get-NxoVmInventory` |
| Performance | `Get-NxoVmCpuReady`, `Get-NxoClusterCpuPeak` |
| Recovery points | `Get-NxoRecoveryPoint`, `New-NxoRecoveryPoint`, `Remove-NxoRecoveryPoint`, `Invoke-NxoRecoveryPointCleanup` |
| Upgrades | `Test-NxoUpgradeReadiness` |

## Complete Workflow Example

A typical rolling AOS/AHV upgrade of one cluster:

```powershell
$cred = Get-Credential
Connect-NxoPrismCentral -Server pc01.example.local -Credential $cred -SkipCertificateCheck

# 1. Resources with one host down: CPU peak of the last 7 days, CPU Ready of the last day
Get-NxoClusterCpuPeak -ClusterName NTNX-CL01 | Format-Table
Get-NxoVmCpuReady -ClusterName NTNX-CL01 | Where-Object Status -eq 'WARN' | Format-Table

# 2. Readiness check with NCC, justifications and HTML report for the change
$check = Test-NxoUpgradeReadiness -ClusterName NTNX-CL01 -ChangeId CHG0012345 -NccReportRecipient ops@example.com
$check | Format-Table Check, Result, Value, Justification
$check[0].ReportPath

# 3. Safety net before the upgrade
New-NxoRecoveryPoint -CategoryKey Patching -CategoryValue NTNX-CL01 -RecoveryPointName PreUpgrade -RetentionDays 7

# 4. After the upgrade: inventory with NGT versions
Get-NxoVmInventory -ClusterName NTNX-CL01 | Where-Object NGT_UpdateNeeded | Format-Table VM, NGT_Version, NGT_Available

Disconnect-NxoPrismCentral
```

## Pipeline Examples

```powershell
# Recovery points of the VMs of one cluster
Get-NxoVmInventory -ClusterName NTNX-CL01 -ExcludePoweredOff | New-NxoRecoveryPoint -RecoveryPointName PrePatch

# Delete expired recovery points of one VM without prompting
Get-NxoRecoveryPoint -VmName SQL01 | Where-Object Expiry -lt (Get-Date) | Remove-NxoRecoveryPoint -Confirm:$false

# Inventory of two Prism Central instances in one CSV
Connect-NxoPrismCentral -Server pc01, pc02 -Credential $cred
Get-NxoVmInventory | Export-Csv .\inventory.csv -Delimiter ';' -NoTypeInformation -Encoding utf8

# Only one of the connected Prism Central instances
Get-NxoVmInventory -Server pc02 | Measure-Object
```

## Error Handling

- A Prism Central that fails (unreachable, no permission) produces a warning; the other instances are still processed.
- A failing VM or cluster inside a command produces a warning; the remaining ones are still processed.
- `Connect-NxoPrismCentral` writes an error per address that cannot be connected, with the reason (wrong password, missing permission, missing v4 API, certificate not trusted).
- Commands without connection stop with "Not connected to any Prism Central".
- Use `-Verbose` to see the API calls, the negotiated API revisions and the full error responses.

## Best Practices

- Connect to every Prism Central that replicates recovery points with the others before running `Invoke-NxoRecoveryPointCleanup`; otherwise a replicated recovery point can look as if its VM was deleted.
- Start the cleanup with `-WhatIf -ExportCsv` and keep the same `-LogDirectory` for all runs, so the storage history can be compared (`-StorageReport` a day later).
- Run `Test-NxoUpgradeReadiness` per cluster with `-ChangeId` and attach the HTML report to the change.
- Use an account that can see all VMs; VMs that cannot be read are never reported as missing.

## Security Considerations

- The credential is kept in memory for the session only; `Disconnect-NxoPrismCentral` removes it. Nothing is written to disk.
- Certificates are validated unless `-SkipCertificateCheck` is used. Prefer a trusted certificate on Prism Central.
- `Remove-NxoRecoveryPoint` asks per recovery point (ConfirmImpact High); `Invoke-NxoRecoveryPointCleanup` asks you to type the number of recovery points before deleting.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `cannot connect ... use -SkipCertificateCheck` | Prism Central uses a self-signed certificate |
| `the v4 API is not available` | Prism Central older than pc.2024.1, or the API gateway is not reachable on port 9440 |
| `Could not resolve cluster names` warning | The account cannot read clustermgmt; extIds are shown instead |
| Empty `DiskTotalGB`, `MAC` or `IP` | Check the raw VM with `-Verbose` or the Prism API explorer; field paths follow the v4 schema |
| Many rate-limit warnings | Prism Central throttles the API; lower `-BatchSize` for the cleanup |

## Resources

- [Nutanix v4 API reference](https://developers.nutanix.com/)
- [Nutanix v4 API user guide](https://www.nutanix.dev/nutanix-api-user-guide/)
- [nutanix-ps-scripts](https://github.com/mcruise40/nutanix-ps-scripts) (the scripts this module replaces)
