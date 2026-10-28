function GetNxoVmNetworkInfo {
    <#
    .SYNOPSIS
        Collects MAC addresses, IP addresses and subnet extIds of a VM.

    .DESCRIPTION
        Internal helper. From API revision v4.1 on, a VM's NIC carries both the new structures
        (nicBackingInfo / nicNetworkInfo) and the legacy ones (backingInfo / networkInfo). The
        new ones are used, the legacy ones are the fallback. IPs include the configured (IPAM)
        address, secondary addresses and the addresses learned from the guest - on networks
        without IPAM only the learned ones are filled.

    .PARAMETER Vm
        A vmm.v4.ahv.config.Vm object.

    .EXAMPLE
        GetNxoVmNetworkInfo -Vm $vm

    .OUTPUTS
        PSCustomObject with MacAddress, IpAddress and SubnetExtId (arrays)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Vm
    )

    $macs = [System.Collections.Generic.List[string]]::new()
    $ips = [System.Collections.Generic.List[string]]::new()
    $subnets = [System.Collections.Generic.List[string]]::new()

    foreach ($nic in @($Vm.nics | Where-Object { $null -ne $_ })) {
        $backing = if ($nic.nicBackingInfo) { $nic.nicBackingInfo } else { $nic.backingInfo }
        $network = if ($nic.nicNetworkInfo) { $nic.nicNetworkInfo } else { $nic.networkInfo }

        if ($backing.macAddress) { $macs.Add([string]$backing.macAddress) }
        if ($null -eq $network) { continue }

        if ($network.subnet.extId) { $subnets.Add([string]$network.subnet.extId) }

        $addresses = @(
            $network.ipv4Config.ipAddress.value
            @($network.ipv4Config.secondaryIpAddressList).value
            @($network.ipv4Info.learnedIpAddresses).value
        )
        foreach ($address in ($addresses | Where-Object { $_ })) { $ips.Add([string]$address) }
    }

    return [PSCustomObject]@{
        MacAddress  = $macs.ToArray()
        IpAddress   = $ips.ToArray()
        SubnetExtId = $subnets.ToArray()
    }
}
