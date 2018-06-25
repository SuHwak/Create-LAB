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
    while($VMHeartBeat -notmatch "OkApplications")
    {
        Start-Sleep -Seconds 5
        Write-Host -ForegroundColor Yellow "$VMname not ready. Waiting"
        $VMHeartBeat = (Get-VM -Name $VMName).HeartBeat
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

function Set-VMHostName ($VMName,$global:credentials) {

    Wait-VM -Vmname $VMName

    $HadToRename = Invoke-Command -VMName $VMName -Credential $global:credentials -ArgumentList $VMName {
        if ($env:COMPUTERNAME -ne $args[0]) {
            Write-Host -fore Yellow "This VM does not have the correct name, renaming it now, then restarting it."
            Rename-Computer $args[0]
            $HadToRename = $true
            Restart-Computer -Force
            $HadToRename

        }
        else {
            Write-Host -fore Green "The VM has the correct name."
            $HadToRename = $false
            $HadToRename
        }
    }
    if ($HadToRename) {
        Wait-VM -Vmname $Vmname
    }
}

$domainName = "MIVEX.LAB"
$NetbiosDomainName = $domainName.split(".")[0]

# Set Administrator Password

$adminUsername = "administrator"
$adminCreds = Get-Credential -Message "Provide password" -UserName $adminUsername 

$VmADCreds = New-Object pscredential ("$($NetbiosDomainName)\$($adminUsername)", $adminCreds.Password)
$VmLocalCreds =  New-Object pscredential ($adminUsername, $adminCreds.Password)
$global:credentials = $null

$DownloadSources = @()
$DownloadTarget = "D:\Windows10ent\"
$Win10EntVHDXTarget = "$DownloadTarget\Windows10Ent.vhdx"
$ManagmentVM = "MivexLab-Mgt1"

$Win10EntVHDXFile = Get-ChildItem $DownloadTarget -Filter "Windows10Ent.vhdx"

if (!($Win10EntVHDXFile)) {
    $Windows10entISO = Get-ChildItem $DownloadTarget -Filter "*.iso"
    $Windows10RSAT = Get-ChildItem $DownloadTarget -Filter "*.msu"

    if (!($Windows10entISO)) {
        $DownloadSources += "https://software-download.microsoft.com/download/pr/17134.1.180410-1804.rs4_release_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
    }

    if (!($Windows10entISO)) {
        $DownloadSources += "https://download.microsoft.com/download/1/D/8/1D8B5022-5477-4B9A-8104-6A71FF9D98AB/WindowsTH-RSAT_WS2016-x64.msu"
    }

    foreach ($DownloadSource in $DownloadSources) {
        Start-BitsTransfer -Source $DownloadSource -Destination $DownloadTarget
    }

    $Windows10entISO = Get-ChildItem $DownloadTarget -Filter "*.iso"
    $Windows10entISO = $Windows10entISO | Rename-Item -NewName "Windows10Ent.iso" -PassThru

    $Windows10RSAT = Get-ChildItem $DownloadTarget -Filter "*.msu"
    $Windows10RSAT = $Windows10RSAT | Rename-Item -NewName "Windows10RSAT.msu" -PassThru

    $mountResult = Mount-DiskImage $Windows10entISO -PassThru

    $driveLetter = ($mountResult | Get-Volume).DriveLetter + ":"

    $OriginalWimFile = Get-ChildItem -path $driveLetter -Filter install.wim -Recurse -depth 1 -ErrorAction SilentlyContinue

    . $DownloadTarget\Convert-WindowsImage.ps1

    Convert-WindowsImage -SourcePath $OriginalWimFile.FullName -VHDPath $Win10EntVHDXTarget -DiskLayout UEFI -UnattendPath "$DownloadTarget\unattend.xml" -Package $Windows10RSAT.FullName

    Dismount-DiskImage $mountResult.ImagePath

    $Win10EntVHDXFile = Get-ChildItem $DownloadTarget -Filter "Windows10Ent.vhdx"
}

$CurrentVms = Get-VM

if ($CurrentVms.Name -contains $ManagmentVM) {
    # This Management VM exists at least in name

    Write-Host -fore Yellow $ManagmentVM "exists at least in name. Checking functions..."    

    $ManagmentVM = get-vm -Name $ManagmentVM

    if ($ManagmentVM.state -ne "Running") {
        Write-Host -fore Yellow $ManagmentVM.Name "is NOT running, trying to start it..."
        Start-VM $ManagmentVM.Name
        Write-Host -fore Yellow "Waiting until " $ManagmentVM.Name " has started."
        Wait-VM -VMName $ManagmentVM.Name
        Write-Host -fore Yellow $ManagmentVM.Name " has started."
    }

}
else {

    Write-Host -fore Yellow "$ManagmentVM does not exist yet, creating it now..."
    $vHDManagmentVM = Copy-Item -Path $Win10EntVHDXFile.FullName -Destination "$((Get-VMHost).VirtualHardDiskPath)\$ManagmentVM.vhdx" -PassThru

    $ManagmentVM = New-VM -Name $ManagmentVM -VHDPath $vHDManagmentVM -MemoryStartupBytes 4GB -Generation 2

    Set-VM -Name $ManagmentVM.Name -ProcessorCount 2 -DynamicMemory -MemoryMaximumBytes 6GB -AutomaticCheckpointsEnabled $false
    Get-VMNetworkAdapter -VMName $ManagmentVM.Name | ?{$_.Switchname -eq $null} | Remove-VMNetworkAdapter
    Add-VMNetworkAdapter -VMName $ManagmentVM.Name -SwitchName "LAB-INSIDE" -Name "LAB-INSIDE" -DeviceNaming On
    Start-VM $ManagmentVM.Name
    Write-Host -fore Yellow "Waiting until " $ManagmentVM.Name " has started."
    Wait-VM -VMName $ManagmentVM.Name
    Write-Host -fore Yellow $ManagmentVM.Name " has started."

}

Write-Host -fore Yellow "Checking if " $ManagmentVM.Name " has the correct name."

Set-VMHostName -VMName $ManagmentVM.Name -credentials $global:credentials

Wait-VM -Vmname $ManagmentVM.Name

Invoke-Command -VMName $ManagmentVM.Name -credential $global:credentials -ArgumentList $ManagmentVM.Name,$domainName,$VmADCreds {

    Write-Host -ForegroundColor Yellow "Checking computer role..."

    $DomainRole = (Get-WmiObject -Class Win32_ComputerSystem).DomainRole

    Write-Host -ForegroundColor Yellow "The computer role is: " $DomainRole

    if ($DomainRole -eq 0) {
        Write-Host -fore Yellow "$($args[0]) is not joined into the $($args[1]) domain"

        $DomainAddress1 = Resolve-DnsName $args[1] -Server 192.168.1.2 -ErrorAction SilentlyContinue
        $DomainAddress2 = Resolve-DnsName $args[1] -Server 192.168.1.1 -ErrorAction SilentlyContinue
        if (!($DomainAddress1 -or $DomainAddress2)) {
            # There is no domain available to join.
            Write-Host -fore Red "There is no domain to join!"

            Get-NetAdapterAdvancedProperty

            Break
        }
        else {
            Write-Host -fore Green "We have a domain, joining it now."

            Add-Computer -DomainName $args[1] -Credential $args[2]
        }
    }
}