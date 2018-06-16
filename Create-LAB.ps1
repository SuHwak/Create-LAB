# Assuming Set-ExecutionPolicy RemoteSigned

# Loading Modules
Import-Module BitsTransfer
. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\LAB\Get-FileName.ps1"
# . "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\Convert-WindowsImage.ps1"

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

# $ethernet = Get-NetAdapter -Name Ethernet
# $wifi = Get-NetAdapter -Name Wi-Fi

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
        while ($ISOlocation -notlike "*.iso") {
    
            $ISOlocation = Get-FileName -initialDirectory "G:\ISO's" -FileType "ISO"
            
            # $ISOLocation = Read-Host -prompt "Please provide the path to the ISO file."
            if (!(Get-ChildItem $ISOlocation -ErrorAction SilentlyContinue) -or $ISOlocation -notlike "*.iso") {
            
                Write-Host -ForegroundColor Red "$ISOlocation does not exist or is not an ISO file."
                $ISOlocation = $null
            }
            else {
                $mountResult = Mount-DiskImage -ImagePath $ISOlocation -PassThru
            
                $driveLetter = ($mountResult | Get-Volume).DriveLetter + ":"
            
                $OriginalWimFile = Get-ChildItem -path $driveLetter -Filter install.wim -Recurse -ErrorAction SilentlyContinue
                if  (!($OriginalWimFile)) {
                    Write-Host -ForegroundColor red "$isolocation mounted on $driveletter does not contain a install.wim file"
                    
                    $ISOlocation = $null
                }  
            }

        }
        
        Write-Host -ForegroundColor Green "Copying, please wait"

        Start-BitsTransfer -Source $OriginalWimFile.FullName -Destination $InstallWimLocation -Description "Copying Install.wim file" -DisplayName "Copying..." 
        
        Write-Host -ForegroundColor Green "Done"

        
    }

    if ($mountResult) {
        
        Dismount-DiskImage $mountResult.ImagePath
    }

}

$WinDCCoreWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCCoreFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory

if (!$WinDCCoreWimFile) {
    $InstallWimFileImages = Get-WindowsImage -ImagePath $WimFile.FullName

    $WinDCCoreImage = $InstallWimFileImages | ?{$_.ImageName -match "Datacenter" -and $_.ImageName -notmatch "Desktop" }

    Export-WindowsImage -SourceImagePath $WimFile.FullName -SourceIndex $WinDCCoreImage.ImageIndex -DestinationImagePath $InstallWimLocation\$WinDCCoreFileName -DestinationName "Windows Datacenter Core"
    $WinDCCoreWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCCoreFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory

}

$WinDCGuiWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCGuiFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory

if (!$WinDCGuiWimFile) {
    $InstallWimFileImages = Get-WindowsImage -ImagePath $WimFile.FullName

    $WinDCGuiImage = $InstallWimFileImages | ?{$_.ImageName -match "Datacenter" -and $_.ImageName -match "Desktop" }

    Export-WindowsImage -SourceImagePath $WimFile.FullName -SourceIndex $WinDCGuiImage.ImageIndex -DestinationImagePath $InstallWimLocation\$WinDCGuiFileName -DestinationName "Windows Datacenter Desktop Experience"
    $WinDCGuiWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCGuiFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory

}







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

# Now applying all the updates to the main offline install.wim file

