# Assuming Set-ExecutionPolicy RemoteSigned

# Loading Modules
. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\Get-FileName.ps1"
# . "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\Convert-WindowsImage.ps1"

# Setting Variables

$domainController = "MivexLab-DC1"
$domainName = "MIVEX.LAB"
$memberServersCount = 2
$ISOlocation = $null # will contain the path to the ISO file we use to build an image
$InstallWimLocation = $null # Will contain the path where the WIM file will be copied to and saved for future use

# $ethernet = Get-NetAdapter -Name Ethernet
# $wifi = Get-NetAdapter -Name Wi-Fi

# Set Administrator Password

$adminUsername = "Administrator"
$adminPassword = "Passw0rd" 
$adminSecPassword = $adminPassword | ConvertTo-SecureString -AsPlainText -Force

$secstr = New-Object -TypeName System.Security.SecureString
$adminPassword.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $adminUsername, $secstr

if (!$ISOlocation) {
    while ($ISOlocation -notlike "*.iso") {
        
        $ISOLocation = Read-Host -prompt "Please provide the path to the ISO file."
        if (!(Get-ChildItem $ISOlocation -ErrorAction SilentlyContinue) -or $ISOlocation -notlike "*.iso") {
        
            Write-Host -ForegroundColor Red "$ISOlocation does not exist or is not an ISO file."
            $ISOlocation = $null
        
        }

        $mountResult = Mount-DiskImage -ImagePath $ISOlocation -PassThru
        
        $driveLetter = ($mountResult | Get-Volume).DriveLetter + ":"

        $OriginalWimFile = Get-ChildItem -path $driveLetter -Filter install.wim -Recurse -ErrorAction SilentlyContinue
        if  (!($OriginalWimFile)) {
            Write-Host -ForegroundColor red "$isolocation mounted on $driveletter does not contain a install.wim file"
            Dismount-DiskImage $ISOlocation
            $ISOlocation = $null
        }
    }
}


if (!$InstallWimLocation) {
    while (!($InstallWimLocation)) {
        
        $InstallWimLocation = Read-Host -prompt "Please provide the path to where the install.wim file may be copied to."

        if (!(Test-Path $InstallWimLocation -ErrorAction SilentlyContinue) -or (Get-ChildItem $InstallWimLocation -Recurse).count -ne 0) { # Test-Path tests if the folder exists, 
                                                                                                                        # counterintuitively, get-childitem returns True if it is empty, and we want the folder to be empty
        
            Write-Host -ForegroundColor Red "$InstallWimLocation does not exist or is not empty."
            $InstallWimLocation = $null
        
        }

        else {
            Write-Host -ForegroundColor Green "Copying, please wait"
            Copy-Item -Path $OriginalWimFile.FullName -Destination $InstallWimLocation
        }
    }
}

