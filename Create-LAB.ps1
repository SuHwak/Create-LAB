# Assuming Set-ExecutionPolicy RemoteSigned

# Loading Modules
Import-Module BitsTransfer
. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\LAB\Get-FileName.ps1"

# Setting Variables

$domainController = "MivexLab-DC1"
$domainName = "MIVEX.LAB"
$memberServersCount = 2
$ISOlocation = $null # will contain the path to the ISO file we use to build an image
$InstallWimLocation = $null # Will contain the path where the WIM file will be copied to and saved for future use
$WimFile = $null
$WinDCCoreFileName = "WinDCCore.wim"
$WinDCGuiFileName = "WinDCGui.wim"
$WindowsUpdatesLocation = "G:\ISO's\Microsoft\WinUpdates\w100-x64\glb"
$LabSwitches = @()

# Set Administrator Password

$adminUsername = "Administrator"
$adminPassword = "Passw0rd" 
$adminSecPassword = $adminPassword | ConvertTo-SecureString -AsPlainText -Force

$secstr = New-Object -TypeName System.Security.SecureString
$adminPassword.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $adminUsername, $secstr

# Find out the ISO file location which contains the Windows image

# Find the location where the WIM file might be copied to, if it doesn't exist yet
while (!($WimFile)) {

    if (!($InstallWimLocation)) {

    $InstallWimLocation = Get-FolderName
    
    }

    $WimFile = Get-ChildItem -Path $InstallWimLocation -Filter "Install.wim" -ErrorAction SilentlyContinue
    
    if ($WimFile) { 
        
        Write-Host -ForegroundColor Green "Found existing wim file $($Wimfile.name)"
    }

    else {

        Write-Host -ForegroundColor yellow "Did not find the install.wim file @ $InstallWimLocation, going to extract it now"
        while ($ISOlocation -notlike "*.iso") {
    
            $ISOlocation = Get-FileName -initialDirectory "G:\ISO's" -FileType "ISO"
            Write-Host -ForegroundColor Green "Checking if this is a good iso file"
            
            if (!(Get-ChildItem $ISOlocation -ErrorAction SilentlyContinue) -or $ISOlocation -notlike "*.iso") {
            
                Write-Host -ForegroundColor Red "$ISOlocation does not exist or is not an ISO file."
                $ISOlocation = $null
            }
            else {
                Write-Host -ForegroundColor Green "Mounting the ISO file"
                $mountResult = Mount-DiskImage -ImagePath $ISOlocation -PassThru
            
                $driveLetter = ($mountResult | Get-Volume).DriveLetter + ":"
            
                $OriginalWimFile = Get-ChildItem -path $driveLetter -Filter install.wim -Recurse -depth 1 -ErrorAction SilentlyContinue
                if  (!($OriginalWimFile)) {
                    Write-Host -ForegroundColor red "$isolocation mounted on $driveletter does not contain a install.wim file"
                    
                    $ISOlocation = $null
                }

                Write-Host -ForegroundColor Green "Found the install.wim"
            }

        }
        
        Write-Host -ForegroundColor Green "Copying the install.wim file, please wait"

        Start-BitsTransfer -Source $OriginalWimFile.FullName -Destination $InstallWimLocation -Description "Copying Install.wim file" -DisplayName "Copying..." 
        
        Write-Host -ForegroundColor Green "Done"

        
    }

    if ($mountResult) {
        Write-Host -ForegroundColor Green "Dismounting the iso."
        Dismount-DiskImage $mountResult.ImagePath
    }

}

Write-Host -ForegroundColor Yellow "Checking if the Windows Datacenter Core edition wim file already exists"
$WinDCCoreWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCCoreFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory

if (!$WinDCCoreWimFile) {

    Write-Host -ForegroundColor Green "Did not find the Windows Datacenter Core edition wim file"
    $InstallWimFileImages = Get-WindowsImage -ImagePath $WimFile.FullName

    $WinDCCoreImage = $InstallWimFileImages | ?{$_.ImageName -match "Datacenter" -and $_.ImageName -notmatch "Desktop" }
    
    Write-Host -ForegroundColor Green "Creating the Windows Datacenter Gui edition wim file"
    Export-WindowsImage -SourceImagePath $WimFile.FullName -SourceIndex $WinDCCoreImage.ImageIndex -DestinationImagePath $InstallWimLocation\$WinDCCoreFileName -DestinationName "Windows Datacenter Core"
    $WinDCCoreWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCCoreFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory

}
Write-Host -ForegroundColor Green "Found or created the Windows Datacenter Core edition wim file"
Write-Host -ForegroundColor Yellow "Checking if the Windows Datacenter Gui edition wim file already exists"
$WinDCGuiWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCGuiFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory

if (!$WinDCGuiWimFile) {

    Write-Host -ForegroundColor Green "Did not find the Windows Datacenter Gui edition wim file"
    $InstallWimFileImages = Get-WindowsImage -ImagePath $WimFile.FullName

    $WinDCGuiImage = $InstallWimFileImages | ?{$_.ImageName -match "Datacenter" -and $_.ImageName -match "Desktop" }

    Write-Host -ForegroundColor Green "Creating the Windows Datacenter Gui edition wim file"
    Export-WindowsImage -SourceImagePath $WimFile.FullName -SourceIndex $WinDCGuiImage.ImageIndex -DestinationImagePath $InstallWimLocation\$WinDCGuiFileName -DestinationName "Windows Datacenter Desktop Experience"
    $WinDCGuiWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCGuiFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory

}
Write-Host -ForegroundColor Green "Found or created the Windows Datacenter Gui edition wim file"

Write-Host -ForegroundColor Yellow "Searching for any updates in $WindowsUpdatesLocation"
$UpdateFiles = Get-ChildItem -path $WindowsUpdatesLocation\* -Include *.cab, *.msu | sort LastWriteTime

Write-Host -ForegroundColor Green "Found $($Updatefiles.count) update(s)"

if (!(Test-Path "G:\MountedWimDCCore")) {
    New-Item -ItemType "Directory" -Path G:\MountedWimDCCore
}
if (!(Test-Path "G:\MountedWimDCGui")) {
    New-Item -ItemType "Directory" -Path G:\MountedWimDCGui
}
if (!(Test-Path "$WindowsUpdatesLocation\Done")) {
    New-Item -ItemType "Directory" -Path "$WindowsUpdatesLocation\Done"
}

Write-Host -ForegroundColor Green "Mounting the Windows Server wim files to be able to apply updates"
$DISMMountResultWinDCCore = Mount-WindowsImage -ImagePath $WinDCCoreWimFile.FullName -path "G:\MountedWimDCCore" -Index 1 
$DISMMountResultWinDCGui = Mount-WindowsImage -ImagePath $WinDCGuiWimFile.FullName -path "G:\MountedWimDCGui" -Index 1 

Write-Host -ForegroundColor Green "Updating..."
foreach ($UpdateFile in $UpdateFiles) {
    Write-Host -ForegroundColor Green "Applying Update $($UpdateFile.Name)"
    Add-WindowsPackage -Path $DISMMountResultWinDCCore.Path -PackagePath $UpdateFile.FullName -LogPath G:\DISMLog\DismDCCore.log -ErrorAction SilentlyContinue
    Add-WindowsPackage -Path $DISMMountResultWinDCGui.Path -PackagePath $UpdateFile.FullName -LogPath G:\DISMLog\DismDCGui.log -ErrorAction SilentlyContinue

    Move-Item $UpdateFile.FullName -Destination "$WindowsUpdatesLocation\Done" -Force
}

Write-Host -ForegroundColor Green "Done applying updates, dismounting the wim files, saving changes"

Dismount-WindowsImage -path $DISMMountResultWinDCCore.path -Save
Dismount-WindowsImage -path $DISMMountResultWinDCGui.path -Save

Write-Host -ForegroundColor Green "Creating the vSwitches if they do not exist yet"

# Create the virtual switches if they are missing 
$LabSwitches = Get-VMSwitch | Where-Object{$_.Name -match "LAB"} | %{$_.Name}

if ($LabSwitches -notcontains "LAB-OUTSIDE") {
    Write-Host -ForegroundColor Yellow "Switch LAB-OUTSIDE does not yet exist..."
    $PhysicalNetworkAdapters = Get-NetAdapter -Physical

    $Measure = $PhysicalNetworkAdapters | measure

    Write-Host "Which adapter do you want to user for the LAB-OUTSIDE vSwitch?"
    $Menu = @{}
    for ($Counter = 1; $Counter -le $Measure.Count; $Counter++) {
        Write-Host -fore Green "$Counter. $($PhysicalNetworkAdapters[$counter-1].InterfaceDescription)"
        $Menu.Add($Counter,($PhysicalNetworkAdapters[$counter-1].ifAlias ))
    }

    [int]$Answer = Read-Host "Choose the adapter"
    $SelectedNetAdapter = $Menu.item($Answer)

    Write-Host -fore Yellow "Creating the switch now, Please wait. The connection might be interupted!"

    New-VMSwitch -Name "LAB-OUTSIDE" -NetAdapterName $SelectedNetAdapter
}

if ($LabSwitches -notcontains "LAB-INSIDE") {
    Write-Host -ForegroundColor Yellow "Switch LAB-INSIDE does not yet exist, creating it now..."
    New-VMSwitch -SwitchType Private -Name "LAB-INSIDE"
}

