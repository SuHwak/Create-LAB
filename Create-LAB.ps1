# Assuming Set-ExecutionPolicy RemoteSigned


# Loading Modules
. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\LAB\Get-FileName.ps1"

# Setting Variables

$WantedDomainControllers = "MivexLab-DC1","MivexLab-DC2"
$domainName = "MIVEX.LAB"
# $memberServersCount = 2

# Set Administrator Password

$adminUsername = "Administrator"
$adminPassword = "2@Joshuamm" 
$adminSecPassword = $adminPassword | ConvertTo-SecureString -AsPlainText -Force

$secstr = New-Object -TypeName System.Security.SecureString
$adminPassword.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $adminUsername, $secstr

function Wait-VM
{
    param($VMName)
    Start-Sleep 15
    while((Get-VM -Name $VMName).HeartBeat -ne  'OkApplicationsHealthy')
    {
        Start-Sleep -Seconds 5
        Write-Host -ForegroundColor Yellow "$VMname not ready. Waiting"
    }
    Write-Host -ForegroundColor Green "The VM status is now: "(Get-VM -Name $VMName).HeartBeat

    $session = New-PSSession -VMName $VMName -Credential $credentials -ErrorAction SilentlyContinue

    while (!($session)) {

        Write-Host -ForegroundColor Yellow "We can't setup a PowerShell Session yet. Waiting 5 seconds"
        Start-Sleep 5
        $session = New-PSSession -VMName $VMName -Credential $credentials -ErrorAction SilentlyContinue
        
    }

    Remove-PSSession $session
}

function Set-VMHostName ($VMName,$credentials) {

    Invoke-Command -VMName $VMName -Credential $credentials -ArgumentList $VMName {
        if ($env:COMPUTERNAME -ne $VMName) {
            Write-Host -fore Yellow "This VM does not have the correct name"
            Rename-Computer $args[0].Name
            Restart-Computer
        }
    }
    Wait-VM -VMName $VMName
}

function New-ADForest ($VMName, $credentials, $DomainName, $DomainAdminSecurePassword) {
    Invoke-Command -VMName $VMName -Credential $credentials -ArgumentList $VMName, $DomainName, $DomainAdminSecurePassword, $credentials {

        function Set-VmDCIpAddress {
            Write-Host -fore Yellow "Making sure the internal network adapter is configured"
            $InternalVMAdapter = Get-NetAdapterAdvancedProperty -DisplayName "Hyper-V Network Adapter Name" | where {$_.DisplayValue -eq "LAB-INSIDE"}
            if ($args[0] -eq "MivexLab-DC1") {
                Write-Host -fore Yellow "This server is $($Args[0])"
                New-NetIPAddress -InterfaceAlias $InternalVMAdapter.InterfaceAlias -AddressFamily IPv4 -IPAddress 192.168.1.1 -DefaultGateway 192.168.1.1 -PrefixLength 24
                Set-DnsClientServerAddress -InterfaceAlias $InternalVMAdapter.InterfaceAlias -ServerAddresses ("192.168.1.1","192.168.1.2")

            }
            elseif ($args[0] -eq "MivexLab-DC2") {
                Write-Host -fore Yellow "This server is $($Args[0])"
                New-NetIPAddress -InterfaceAlias $InternalVMAdapter.InterfaceAlias -AddressFamily IPv4 -IPAddress 192.168.1.2 -DefaultGateway 192.168.1.1 -PrefixLength 24
                Set-DnsClientServerAddress -InterfaceAlias $InternalVMAdapter.InterfaceAlias -ServerAddresses ("192.168.1.1","192.168.1.2")

            }

        }
        
        $DomainRole = (Get-WmiObject -Class Win32_ComputerSystem).DomainRole
        
        if ($DomainRole -eq 2) {
            # Needs testing
            $Args[0]
            Write-Host -fore Yellow "$VMName is not joined into the $($args[1]) domain"
            $DomainAddress = Resolve-DnsName $args[1] -ErrorAction SilentlyContinue
            if (!($DomainAddress)) {
                # There is no domain available to join.
                Write-Host -fore Yellow "There is no domain to join, preparing this domain controller to become the first"
                
                Set-VmDCIpAddress

                if (!((Get-WindowsFeature AD-Domain-Services).Installed)) {
                    Write-Host -fore Yellow "Installing the prerquisite binaries for domain services"

                    Install-WindowsFeature AD-Domain-Services, DNS -IncludeAllSubFeature -IncludeManagementTools
                }

                Write-Host -fore Yellow "Creating the new forest & domain"

                Install-ADDSForest -DomainName $Args[1] -SafeModeAdministratorPassword $args[2] -ForestMode 7 -Force
            }
            else {
                
            }
        }

        elseif ($DomainRole -eq 3) {
            Write-Host -fore Yellow "This server is a member of a domain, but not a domain controller"
            if ((Get-WmiObject win32_ComputerSystem).domain -ne $args[1]) {
                Write-Host -fore Red "This server is a member of a wrong domain! Exiting"
                EXIT
            }
            
            else {
                Set-VmDCIpAddress

                if (!((Get-WindowsFeature AD-Domain-Services).Installed)) {
                    Write-Host -fore Yellow "Installing the prerquisite binaries for domain services"

                    Install-WindowsFeature AD-Domain-Services, DNS -IncludeAllSubFeature -IncludeManagementTools
                }

                Install-ADDSDomainController -DomainName $Args[1] -Credential $Args[3] -WhatIf
            }
        }

        elseif ($DomainRole -eq 4) {
            if ((Get-WmiObject win32_ComputerSystem).domain -ne $args[1]) {
                Write-Host -fore Red "This server is a member of a wrong domain! Exiting"
                EXIT
            }
            else {
                Write-Host -fore Green "This server is already a backup domain controller"
            }
        }
        elseif ($DomainRole -eq 5) {
            if ((Get-WmiObject win32_ComputerSystem).domain -ne $args[1]) {
                Write-Host -fore Red "This server is a member of a wrong domain! Exiting"
                EXIT
            }
            else {
                Write-Host -fore Green "This server is already a primary domain controller"
            }
        }
    }
}

# These are not modules
. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\LAB\Prepare-VhdxFiles.ps1"

. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\LAB\Create-vSwitches.ps1"

$CurrentVms = Get-VM

foreach ($WantedDomainController in $WantedDomainControllers) {
    if ($CurrentVms.Name -contains $WantedDomainController) {
        # This domain controller exists at least in name
        
        $domainController = get-vm -Name $WantedDomainController
        
        if ($domainController.state -ne "Running") {
            Start-VM $domainController.Name
            Wait-VM -VMName $domainController.Name
        }
        
        Set-VMHostName -VMName $domainController.Name -credentials $credentials

        New-ADForest -VMName $domainController.Name -credentials $credentials -DomainName $domainName -DomainAdminSecurePassword $adminSecPassword

    }
    else {
        # This domain controller does not exist
        $vHDDomainController = Copy-Item -Path $WinDCCoreVHDXFile -Destination "$((Get-VMHost).VirtualHardDiskPath)\$WantedDomainController.vhdx" -PassThru
        $domainController = New-VM -Name $WantedDomainController -VHDPath $vHDDomainController -MemoryStartupBytes 2GB -Generation 2
        Set-VM -Name $domainController.Name -ProcessorCount 2 -DynamicMemory -MemoryMaximumBytes 4GB -AutomaticCheckpointsEnabled $false
        Add-VMNetworkAdapter -VMName $domainController.Name -SwitchName "LAB-OUTSIDE" -Name "LAB-OUTSIDE" -DeviceNaming On
        Add-VMNetworkAdapter -VMName $domainController.Name -SwitchName "LAB-INSIDE" -Name "LAB-INSIDE" -DeviceNaming On

        Start-VM -Name $domainController.Name
        Wait-VM -VMName $domainController.Name

        Set-VMHostName -VMName $domainController.Name -credentials $credentials

        New-ADForest -VMName $domainController.Name -credentials $credentials -DomainName $domainName -DomainAdminSecurePassword $adminSecPassword
    }
}
