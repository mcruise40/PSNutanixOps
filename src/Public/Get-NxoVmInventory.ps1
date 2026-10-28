function Get-NxoVmInventory {
    <#
    .SYNOPSIS
        Returns an asset inventory of the AHV VMs of the connected Prism Central instances.

    .DESCRIPTION
        One object per VM with sizing (vCPU, memory, disks), guest OS and Nutanix Guest Tools
        (NGT) status, boot and vTPM configuration, network (MAC, IP, subnet), DR protection,
        categories, placement (cluster, host) and creation/update time. Powered-off VMs are
        included unless -ExcludePoweredOff is used.

        Cluster, host, category and subnet names are resolved via lookups. If a lookup fails,
        the extId is shown instead and a warning is written.

        guestTools is missing on VMs where NGT was never enabled - the NGT columns are then
        False or empty.

    .PARAMETER Server
        Only query these connected Prism Central instance(s). Default: all connections.

    .PARAMETER VmName
        Only include these VM(s). Case-insensitive, wildcards (*) are supported.

    .PARAMETER ClusterName
        Only include VMs on these cluster(s) (Prism Element cluster name, case-insensitive).

    .PARAMETER ExcludePoweredOff
        Skip VMs that are not powered on.

    .EXAMPLE
        Get-NxoVmInventory | Export-Csv -Path .\VM-Inventory.csv -Delimiter ';' -NoTypeInformation -Encoding utf8

        Full inventory of all connected Prism Central instances, exported to CSV.

    .EXAMPLE
        Get-NxoVmInventory | Where-Object { -not $_.NGT_Installed -or $_.NGT_UpdateNeeded } |
            Format-Table VM, Cluster, NGT_Version, NGT_Available

        VMs without NGT or with an outdated NGT version.

    .EXAMPLE
        Get-NxoVmInventory -ClusterName NTNX-CL01 -ExcludePoweredOff | Format-Table

        Powered-on VMs of one cluster.

    .INPUTS
        None

    .OUTPUTS
        PSCustomObject (PSNutanixOps.VmInventory)

    .NOTES
        Field paths for disks (disks[].backingInfo.diskSizeBytes) and NICs follow the v4
        schema; both the v4.1+ NIC structures and the legacy ones are read.

    .LINK
        Connect-NxoPrismCentral
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Server,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('VmNames')]
        [string[]]
        $VmName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterNames')]
        [string[]]
        $ClusterName,

        [Parameter()]
        [switch]
        $ExcludePoweredOff
    )

    Write-Verbose "Starting $($MyInvocation.MyCommand)"
    $connections = GetNxoTargetConnection -Server $Server
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($connection in $connections) {
        $pc = $connection.Server
        Write-Verbose "Prism Central $pc - reading VM inventory"

        try {
            $vms = @(GetNxoPagedList -Connection $connection -Namespace vmm -Path '/ahv/config/vms' -Activity "$($pc): reading VMs")
        } catch {
            Write-Verbose "$($MyInvocation.MyCommand) failed for '$pc': $_"
            Write-Warning "Skipping Prism Central $pc - VM list failed: $($_.Exception.Message)"
            continue
        }

        $clusterNames = GetNxoNameMap -Connection $connection -Kind Cluster
        $hostNames = GetNxoNameMap -Connection $connection -Kind Host
        $categoryNames = GetNxoNameMap -Connection $connection -Kind Category
        $subnetNames = GetNxoNameMap -Connection $connection -Kind Subnet

        if ($VmName) {
            $vms = @($vms | Where-Object {
                    $candidate = $_.name
                    @($VmName | Where-Object { $candidate -like $_ }).Count -gt 0
                })
        }
        if ($ClusterName) {
            if ($clusterNames.Count -eq 0) {
                Write-Warning "Skipping Prism Central $pc - -ClusterName was given, but cluster names could not be resolved."
                continue
            }
            $vms = @($vms | Where-Object {
                    $resolved = $clusterNames[$_.cluster.extId]
                    $resolved -and ($ClusterName -contains $resolved)
                })
        }
        if ($ExcludePoweredOff) {
            $vms = @($vms | Where-Object { $_.powerState -eq 'ON' })
        }
        if (-not $vms.Count) {
            Write-Warning "No matching VMs on $pc."
            continue
        }

        foreach ($vm in $vms) {
            $guestTools = $vm.guestTools
            $threads = if ($vm.numThreadsPerCore) { [int]$vm.numThreadsPerCore } else { 1 }
            $diskSizes = @(@($vm.disks).backingInfo.diskSizeBytes | Where-Object { $null -ne $_ })
            $diskSum = if ($diskSizes.Count) { ($diskSizes | Measure-Object -Sum).Sum } else { $null }
            $bootObjectType = GetNxoPropertyValue -InputObject $vm.bootConfig -Name '$objectType'
            $network = GetNxoVmNetworkInfo -Vm $vm

            $row = [PSCustomObject][ordered]@{
                PrismCentral     = $pc
                Cluster          = ResolveNxoName -Map $clusterNames -ExtId $vm.cluster.extId
                Host             = ResolveNxoName -Map $hostNames -ExtId $vm.host.extId
                VM               = $vm.name
                Description      = $vm.description
                PowerState       = $vm.powerState
                Sockets          = $vm.numSockets
                CoresPerSocket   = $vm.numCoresPerSocket
                vCPU             = [int]$vm.numSockets * [int]$vm.numCoresPerSocket * $threads
                MemoryGB         = if ($vm.memorySizeBytes) { [Math]::Round([double]$vm.memorySizeBytes / 1GB, 2) } else { $null }
                DiskCount        = GetNxoItemCount -Value $vm.disks
                DiskTotalGB      = if ($diskSum) { [Math]::Round([double]$diskSum / 1GB, 2) } else { $null }
                GuestOS          = $guestTools.guestOsVersion
                NGT_Installed    = [bool]$guestTools.isInstalled
                NGT_Enabled      = [bool]$guestTools.isEnabled
                NGT_Reachable    = [bool]$guestTools.isReachable
                NGT_Version      = $guestTools.version
                NGT_Available    = $guestTools.availableVersion
                NGT_UpdateNeeded = TestNxoVersionLower -Installed $guestTools.version -Available $guestTools.availableVersion
                BootType         = if ($bootObjectType) { $bootObjectType -replace '^vmm\.v4\.ahv\.config\.', '' } else { $null }
                vTPM             = [bool]$vm.vtpmConfig.isVtpmEnabled
                MachineType      = $vm.machineType
                MAC              = JoinNxoUnique -Value $network.MacAddress
                IP               = JoinNxoUnique -Value $network.IpAddress
                Subnet           = JoinNxoUnique -Value @($network.SubnetExtId | ForEach-Object { ResolveNxoName -Map $subnetNames -ExtId $_ })
                Protection       = $vm.protectionType
                Categories       = JoinNxoUnique -Value @(@($vm.categories).extId | ForEach-Object { ResolveNxoName -Map $categoryNames -ExtId $_ })
                Created          = ConvertToNxoLocalTime -Timestamp $vm.createTime
                Updated          = ConvertToNxoLocalTime -Timestamp $vm.updateTime
                VmExtId          = $vm.extId
            }
            $row.PSObject.TypeNames.Insert(0, 'PSNutanixOps.VmInventory')
            $results.Add($row)
        }

        Write-Verbose "$($vms.Count) VM(s) read from $pc."
    }

    Write-Verbose "Completed $($MyInvocation.MyCommand)"
    return $results | Sort-Object -Property PrismCentral, Cluster, VM
}
