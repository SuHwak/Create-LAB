# Assuming Set-ExecutionPolicy RemoteSigned

# Loading Modules
. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\LAB\Get-FileName.ps1"

# Setting Variables

$WantedDomainControllers = "MivexLab-DC1","MivexLab-DC2"
$domainName = "MIVEX.LAB"
$NetbiosDomainName = $domainName.split(".")[0]
# $memberServersCount = 2

# Set Administrator Password

$adminUsername = "administrator"
$adminCreds = Get-Credential -Message "Provide password" -UserName $adminUsername 

$VmADCreds = New-Object pscredential ("$($NetbiosDomainName)\$($adminUsername)", $adminCreds.Password)
$VmLocalCreds =  New-Object pscredential ($adminUsername, $adminCreds.Password)
$global:credentials = $null

function Test-Credentials ($Vmname) {
    $global:ConnectionSuccesful = $false
    Write-Host -ForegroundColor Yellow "Testing the connection to " $VMName
    
    $global:vmDomainRoleScript = { $global:vmDomainRole = (Get-WmiObject -computername mivexlab-dc1 -Class Win32_ComputerSystem -Credential $creds).DomainRole; $global:vmDomainRole }
    
    try {
        $session = New-PSSession -VMName $Vmname -Credential $VmADCreds -ErrorAction Stop
        Write-Host -ForegroundColor Green "The domain credentials worked"
        $global:vmDomainRole = Invoke-Command -Session $session -ScriptBlock $global:vmDomainRoleScript
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
        $global:vmDomainRole = Invoke-Command -Session $session -ScriptBlock $global:vmDomainRoleScript
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

    while((Get-VM -Name $VMName).HeartBeat -ne 'OkApplicationsHealthy')
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
}

function Set-VMHostName ($VMName,$global:credentials) {

    Wait-VM -Vmname $VMName

    Invoke-Command -VMName $VMName -Credential $global:credentials -ArgumentList $VMName {
        if ($env:COMPUTERNAME -ne $args[0]) {
            Write-Host -fore Yellow "This VM does not have the correct name, renaming it now, then restarting it."
            Rename-Computer $args[0]
            Restart-Computer
        }
        else {
            Write-Host -fore Green "The VM has the correct name." 
        }
    }
    Wait-VM -VMName $VMName
}

function New-ADForest ($VMName, $credentials, $DomainName, $DomainCreds) {

    $global:vmDomainRole = $null

    while ($global:vmDomainRole -ne 4 -and $global:vmDomainRole -ne 5) {

        Write-Host -ForegroundColor Yellow "Domain Role is: " $global:vmDomainRole
        if ($global:vmDomainRole -eq 3) { # After restart stand-alone server to a member server, the credentials need to change, which doesn't work though the test-credentials function somehow
            $credentials = $VmADCreds
        }
        Invoke-Command -VMName $VMName -Credential $credentials -ArgumentList $VMName, $DomainName, $credentials, $DomainCreds {
            function Set-VmDCIpAddress ($VMName) {
                Write-Host -fore Yellow "Making sure the internal network adapter of server $VMName is configured"
                $InternalVMAdapter = Get-NetAdapterAdvancedProperty -DisplayName "Hyper-V Network Adapter Name" | where {$_.DisplayValue -eq "LAB-INSIDE"}
                if ($VMName -eq "MivexLab-DC1") {
                    Write-Host -fore Yellow "This server is $VMName"
                    New-NetIPAddress -InterfaceAlias $InternalVMAdapter.InterfaceAlias -AddressFamily IPv4 -IPAddress 192.168.1.1 -DefaultGateway 192.168.1.1 -PrefixLength 24
                    Set-DnsClientServerAddress -InterfaceAlias $InternalVMAdapter.InterfaceAlias -ServerAddresses ("192.168.1.1","192.168.1.2")

                }
                elseif ($VMName -eq "MivexLab-DC2") {
                    Write-Host -fore Yellow "This server is $VMName"
                    New-NetIPAddress -InterfaceAlias $InternalVMAdapter.InterfaceAlias -AddressFamily IPv4 -IPAddress 192.168.1.2 -DefaultGateway 192.168.1.1 -PrefixLength 24
                    Set-DnsClientServerAddress -InterfaceAlias $InternalVMAdapter.InterfaceAlias -ServerAddresses ("192.168.1.1","192.168.1.2")

                }
            }
            
            $DomainRole = (Get-WmiObject -Class Win32_ComputerSystem).DomainRole

            Write-Host -ForegroundColor Yellow "The computer role is: " $DomainRole
            if ($DomainRole -eq 2) {
                # Needs testing
                Set-VmDCIpAddress -Vmname $args[0]
                
                Write-Host -fore Yellow "$($args[0]) is not joined into the $($args[1]) domain"
                $DomainAddress1 = Resolve-DnsName $args[1] -Server 192.168.1.2 -ErrorAction SilentlyContinue
                $DomainAddress2 = Resolve-DnsName $args[1] -Server 192.168.1.1 -ErrorAction SilentlyContinue
                if (!($DomainAddress1 -or $DomainAddress2)) {
                    # There is no domain available to join.
                    Write-Host -fore Yellow "There is no domain to join, preparing this domain controller to become the first"

                    if (!((Get-WindowsFeature AD-Domain-Services).Installed)) {
                        Write-Host -fore Yellow "Installing the prerquisite binaries for domain services"

                        Install-WindowsFeature AD-Domain-Services, DNS -IncludeAllSubFeature -IncludeManagementTools
                    }

                    Write-Host -fore Yellow "Creating the new forest & domain"

                    Install-ADDSForest -DomainName $Args[1] -SafeModeAdministratorPassword $args[2].password -ForestMode 7 -Force
                }
                else {
                    Write-Host -fore Yellow "Domain exists, trying to join the server to this domain."

                    Add-Computer -DomainName $Args[1] -Credential $Args[3] -Restart
                }
            }
            elseif ($DomainRole -eq 3) {
                Write-Host -fore Yellow "This server is a member of a domain, but not a domain controller"

                Set-VmDCIpAddress -VMName $Args[0]

                if (!((Get-WindowsFeature AD-Domain-Services).Installed)) {
                    Write-Host -fore Yellow "Installing the prerquisite binaries for domain services"

                    Install-WindowsFeature AD-Domain-Services, DNS -IncludeAllSubFeature -IncludeManagementTools
                }
                
                Install-ADDSDomainController -DomainName $env:userdnsdomain -Credential $Args[2] -SafeModeAdministratorPassword $args[2].password -Force
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

        
        if ($global:vmDomainRole -ne 4 -and $global:vmDomainRole -ne 5) {
            Write-Host -ForegroundColor Yellow $VMName "is restarting now, waiting 15 seconds"
            Start-Sleep 15
            Wait-VM -Vmname $VMName
        }
        elseif ($global:vmDomainRole -eq $null) {
            Write-Host -ForegroundColor Red $global:vmDomainRole "is NULL"
            Wait-VM -Vmname $VMName
            
        }
    }
}

# These are not modules
. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\LAB\Prepare-VhdxFiles.ps1"

. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\LAB\Create-vSwitches.ps1"

$CurrentVms = Get-VM

foreach ($WantedDomainController in $WantedDomainControllers) {
    Write-Host -fore Yellow "We want domain controller(s)"
    if ($CurrentVms.Name -contains $WantedDomainController) {
        # This domain controller exists at least in name

        Write-Host -fore Yellow $WantedDomainController "exists at least in name. Checking functions..."    
        
        $domainController = get-vm -Name $WantedDomainController
        
        if ($domainController.state -ne "Running") {
            Write-Host -fore Yellow $WantedDomainController "is NOT running, trying to start it..."
            Start-VM $domainController.Name
            Write-Host -fore Yellow "Waiting until " $WantedDomainController " has started."
            Wait-VM -VMName $domainController.Name
            Write-Host -fore Yellow $WantedDomainController " has started."
        }
        
        Write-Host -fore Yellow "Checking if " $WantedDomainController " has the correct name."
        Set-VMHostName -VMName $domainController.Name -credentials $global:credentials

        New-ADForest -VMName $domainController.Name -credentials $global:credentials -DomainName $domainName -DomainCreds $VmADCreds

    }
    else {
        Write-Host -fore Yellow "This domain controller does not exist, creating it now. Please wait..."

        $vHDDomainController = Copy-Item -Path $WinDCCoreVHDXFile -Destination "$((Get-VMHost).VirtualHardDiskPath)\$WantedDomainController.vhdx" -PassThru
        $domainController = New-VM -Name $WantedDomainController -VHDPath $vHDDomainController -MemoryStartupBytes 2GB -Generation 2
        Set-VM -Name $domainController.Name -ProcessorCount 2 -DynamicMemory -MemoryMaximumBytes 4GB -AutomaticCheckpointsEnabled $false
        Get-VMNetworkAdapter -VMName $domainController.Name | ?{$_.Switchname -eq $null} | Remove-VMNetworkAdapter
        Add-VMNetworkAdapter -VMName $domainController.Name -SwitchName "LAB-OUTSIDE" -Name "LAB-OUTSIDE" -DeviceNaming On
        Add-VMNetworkAdapter -VMName $domainController.Name -SwitchName "LAB-INSIDE" -Name "LAB-INSIDE" -DeviceNaming On

        Start-VM -Name $domainController.Name
        Wait-VM -VMName $domainController.Name

        Set-VMHostName -VMName $domainController.Name -credentials $global:credentials

        New-ADForest -VMName $domainController.Name -credentials $global:credentials -DomainName $domainName -DomainCreds $VmADCreds
    }

    Write-Host -ForegroundColor White -BackgroundColor Blue  "                 Finished for $WantedDomainController!                 "
}
