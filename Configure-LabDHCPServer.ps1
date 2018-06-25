if (!$domainName) {
    $domainName = "MIVEX.LAB"
}

$NetbiosDomainName = $domainName.split(".")[0]
# $memberServersCount = 2

# Set Administrator Password
if (!$adminUsername) {
   $adminUsername = "administrator" 
}
if (!$adminCreds) {
    $adminCreds = Get-Credential -Message "Provide password" -UserName $adminUsername 
}
$VmADCreds = New-Object pscredential ("$($NetbiosDomainName)\$($adminUsername)", $adminCreds.Password)
$VmLocalCreds =  New-Object pscredential ($adminUsername, $adminCreds.Password)
$global:credentials = $null

function Test-Credentials ($Vmname) {
    $global:ConnectionSuccesful = $false
    Write-Host -ForegroundColor Yellow "Testing the connection to " $VMName
    
    $vmDomainRoleScript = { $DomainRole = (Get-WmiObject -Class Win32_ComputerSystem).DomainRole; Write-Host "DomainRole is:" $DomainRole; $DomainRole }
    
    try {
        $session = New-PSSession -VMName $Vmname -Credential $VmADCreds -ErrorAction Stop
        Write-Host -ForegroundColor Green "The domain credentials worked"
        $global:vmDomainRole = Invoke-Command -Session $session -ScriptBlock $vmDomainRoleScript
        $session | Remove-PSSession
        $session = $null
        $global:credentials = New-Object pscredential ($VmADCreds)
        $global:ConnectionSuccesful = $true

    }
    catch {
        Write-Host -ForegroundColor Red "The domain credentials didn't work"

    }

    try {
        $session = New-PSSession -VMName $Vmname -Credential $VmLocalCreds -ErrorAction Stop
        Write-Host -ForegroundColor Green "The Local credentials worked"
        $global:vmDomainRole = Invoke-Command -Session $session -ScriptBlock $vmDomainRoleScript -Verbose
        $session | Remove-PSSession
        $session = $null
        $global:credentials = New-Object pscredential ($VmLocalCreds)
        $global:ConnectionSuccesful = $true

    }
    catch {
        Write-Host -ForegroundColor Red "The local credentials didn't work"
    }
}

function Wait-VM ($Vmname) {

    Write-Host -fore Yellow "Checking if we can connect to " $VMName
    $VMHeartBeat = (Get-VM -Name $VMName).HeartBeat
    while($VMHeartBeat -ne 'OkApplicationsHealthy' -or $VMHeartBeat -ne "OkApplicationsUnknown")
    {
        Start-Sleep -Seconds 5
        Write-Host -ForegroundColor Yellow "$VMname not ready. Waiting"
    }
    Write-Host -ForegroundColor Green "The VM status is now: "(Get-VM -Name $VMName).HeartBeat
    Write-Host -ForegroundColor Yellow "Testing credentials"
    Test-Credentials -Vmname $VMName

    while (!($global:ConnectionSuccesful)) {

        Write-Host -ForegroundColor Yellow "We can't setup a PowerShell Session yet. Waiting 10 seconds"
        Start-Sleep 10
        Test-Credentials -Vmname $VMName
        
    }
    $VMHeartBeat = (Get-VM -Name $VMName).HeartBeat
}

if (!($WantedDomainControllers)) {
    $domainControllers = $null
    $LocalVMs = Get-VM

    foreach ($LocalVM in $LocalVMs) {
        Wait-VM -Vmname $LocalVM.Name
        if ($global:vmDomainRole -eq 4 -or $global:vmDomainRole -eq 5) {
            $domainControllers += @($LocalVM.Name)
        }
    }
}
else {
    $domainControllers = $WantedDomainControllers
}

if ($domainControllers.Count -lt 1) {
    Write-Host -ForegroundColor Red "We don't have any domain controllers! Please run `"Create-Lab.ps1`" first."
}

Write-Host -fore Yellow "On which of these domain controllers do you want to install the DHCP service?"
$index = 0
foreach ($domainController in $domainControllers) {
    $index++
    Write-Host -ForegroundColor Green "$index. " $domainController
    
}
$DCchoice = $null
while ($DCchoice -le 0 -or $DCchoice -gt $index) {
    [int]$DCchoice = Read-Host "Choose the DC"
}
$WantedDHCPServer = $domainControllers[$DCchoice-1]
Write-Host -fore Green "Chosen DC: " -NoNewline ; Write-Host -ForegroundColor Blue $WantedDHCPServer

Wait-VM -Vmname $WantedDHCPServer

Invoke-Command -VMName $WantedDHCPServer -Credential $global:credentials {
    $DHCPInstalledState = (get-windowsfeature -Name "DHCP").Installed
    $DHCPInstalledState

    if (!($DHCPInstalledState)) {
        Write-Host -ForegroundColor Yellow "The DHCP server role has not yet been installed. Installing now..."
        Install-WindowsFeature -Name "DHCP" -IncludeManagementTools
    }
    else {
        Write-Host -ForegroundColor Green "The DHCP Role has already been installed"
    }
    netsh dhcp add securitygroups
    Restart-service dhcpserver
    # Add-DhcpServerInDC -DnsName DHCP1.corp.contoso.com -IPAddress 192.168.1.1
    # Get-DhcpServerInDC
    # Set-DhcpServerv4DnsSetting -DynamicUpdates "Always" -DeleteDnsRRonLeaseExpiry $True
    # Add-DhcpServerv4Scope -Name "MivexLab DHCP Scope" -StartRange 192.168.1.100 -EndRange 192.168.1.200 -Subnet 255.255.255.0 -leaseduration 4:00:00 -State Active
    # Set-DhcpServerv4OptionValue -ScopeId "MivexLab DHCP Scope" -DnsServer 192.168.1.1, 192.168.1.2 -DNSDomain "Mivex.Lab" -Router 192.168.1.1
    
    $DoWeHaveNAT = Get-NetNat

    if (!$DoWeHaveNAT) {
        New-NetNat -Name "MivexLab-NAT" -InternalIPInterfaceAddressPrefix 192.168.1.0/24
    }
    else {
        Get-NetNat | Remove-NetNat
        New-NetNat -Name "MivexLab-NAT" -InternalIPInterfaceAddressPrefix 192.168.1.0/24
    }


}


