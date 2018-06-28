# Loading Modules
Import-Module BitsTransfer

# Setting Variables

$WimFile = $null
$WinDCCoreFileName = "WinDCCore.wim"
$WinDCGuiFileName = "WinDCGui.wim"
$WindowsUpdatesLocation = "G:\ISO's\Microsoft\Windows Server\WindowsServer2016-Updates"

# Find out the ISO file location which contains the Windows image

# Find the location where the WIM file might be copied to, if it doesn't exist yet

if (!($InstallWimLocation)) {
    . "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\LAB\Get-FileName.ps1"
    $InstallWimLocation = Get-FolderName
    
    }

if (!(Get-ChildItem -Path $InstallWimLocation -Filter "Unattend.Xml")) {
    # Create the XML file
}


while (!($WimFile)) {

    $WimFile = Get-ChildItem -Path $InstallWimLocation -Filter "Install.wim" -ErrorAction SilentlyContinue
    
    if ($WimFile) { 
        
        Write-Host -ForegroundColor Green "Found existing wim file $($Wimfile.name)"
    }

    else {

        Write-Host -ForegroundColor yellow "Did not find the install.wim file @ $InstallWimLocation, going to extract it now"
        while ($ISOlocation -notlike "*.iso") {
    
            $ISOlocation = Get-FileName -initialDirectory "G:\ISO's" -FileType "ISO"
            Write-Host -ForegroundColor Green "Checking if $isolocation is a good iso file"
            
            if (!(Get-ChildItem $ISOlocation -ErrorAction SilentlyContinue) -or $ISOlocation -notlike "*.iso") {
            
                Write-Host -ForegroundColor Red "$ISOlocation does not exist or is not an ISO file."
                $ISOlocation = $null
            }
            else {
                Write-Host -ForegroundColor Green "Mounting the ISO file"
                $mountResult = Mount-DiskImage -ImagePath $ISOlocation -PassThru
            
                $driveLetter = ($mountResult | Get-Volume).DriveLetter + ":"
            
                $OriginalWimFile = Get-ChildItem -path $driveLetter -Filter install.wim -Recurse -depth 1 -ErrorAction SilentlyContinue
                $ConvertWindowsImagePSf = Get-ChildItem -path $driveLetter -Filter Convert-WindowsImage.ps1 -Recurse -depth 2 -ErrorAction SilentlyContinue
                if  (!($OriginalWimFile)) {
                    Write-Host -ForegroundColor red "$isolocation mounted on $driveletter does not contain a install.wim file"
                    
                    $ISOlocation = $null
                }

                Write-Host -ForegroundColor Green "Found the install.wim"
            }

        }
        
        Write-Host -ForegroundColor Green "Copying the install.wim file, please wait"

        Start-BitsTransfer -Source $OriginalWimFile.FullName -Destination $InstallWimLocation -Description "Copying Install.wim file" -DisplayName "Copying..." 
        
        Write-Host -ForegroundColor Yellow "We now have the install.wim file, but we need Convert-WindowsImage script from the ISO as well"
        Start-BitsTransfer -Source $ConvertWindowsImagePSf.FullName -Destination $InstallWimLocation -Description "Copying Convert-WindowsImage.ps1 file" -DisplayName "Copying..." 
        
        Write-Host -ForegroundColor Green "Done"

    }

    if ($mountResult) {
        Write-Host -ForegroundColor Green "Dismounting the iso."
        
        Dismount-DiskImage $mountResult.ImagePath
    }
}

Write-Host -ForegroundColor Yellow "Checking if the Windows Datacenter Core edition wim file already exists"
$WinDCCoreWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCCoreFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory,LastWriteTime

if (!$WinDCCoreWimFile) {

    Write-Host -ForegroundColor Green "Did not find the Windows Datacenter Core edition wim file"
    $InstallWimFileImages = Get-WindowsImage -ImagePath $WimFile.FullName

    $WinDCCoreImage = $InstallWimFileImages | ?{$_.ImageName -match "Datacenter" -and $_.ImageName -notmatch "Desktop" }
    
    Write-Host -ForegroundColor Green "Creating the Windows Datacenter Core edition wim file"
    Export-WindowsImage -SourceImagePath $WimFile.FullName -SourceIndex $WinDCCoreImage.ImageIndex -DestinationImagePath $InstallWimLocation\$WinDCCoreFileName -DestinationName "Windows Datacenter Core"
    $WinDCCoreWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCCoreFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory

}
Write-Host -ForegroundColor Green "Found or created the Windows Datacenter Core edition wim file"
Write-Host -ForegroundColor Yellow "Checking if the Windows Datacenter Gui edition wim file already exists"
$WinDCGuiWimFile = Get-ChildItem -Path $InstallWimLocation -Filter $WinDCGuiFileName -ErrorAction SilentlyContinue | select -Property Name,FullName,Directory,LastWriteTime

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

# avoid downloading updates that we already have
$PreviouslyDoneUpdates =  Get-ChildItem -path $WindowsUpdatesLocation\done\* -Include *.cab, *.msu

# Retrieving new updates

Write-Host -fore green "Checking Windows Update for updates"

$UpdateDate = Get-ChildItem "$WindowsUpdatesLocation\done\" -filter "Updated.log"

if (!$UpdateDate) {
    Write-Host -fore Yellow "We have no record that we updated in the last day, retrieving updates now"
    #& 'G:\ISO''s\Microsoft\wsusoffline\cmd\DownloadUpdates.cmd' w100-x64 glb /verify /includewddefs /includedotnet
    Get-Date | Out-File -FilePath "$WindowsUpdatesLocation\done\Updated.log"
}
elseif ($UpdateDate.LastWriteTime -lt (Get-Date).AddDays(-1)) {
    Write-Host -fore Yellow "We have not updated in the last day, retrieving updates now"
    #& 'G:\ISO''s\Microsoft\wsusoffline\cmd\DownloadUpdates.cmd' w100-x64 glb /verify /includewddefs /includedotnet
    Get-Date | Out-File -FilePath $UpdateDate

}
else {
    Write-Host -fore Green "We have already updated within the last 24 hours. Skipping downloading updates"
}


Write-Host -fore green "Copying new updates, please wait..."
Get-ChildItem -path "G:\ISO's\Microsoft\wsusoffline\client\w100-x64\glb\*" -Include *.cab, *.msu | where{$PreviouslyDoneUpdates.name -notcontains $_.Name} | %{Write-Host "Copying $_"; Copy-Item $_ -Destination $WindowsUpdatesLocation}

$UpdateFiles = Get-ChildItem -path $WindowsUpdatesLocation\* -Include *.cab, *.msu | sort LastWriteTime

Write-Host -ForegroundColor Green "Found $($Updatefiles.count) new update(s)"

if ($Updatefiles) {
        
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

    Write-Host -ForegroundColor Green "Done saving the images into the wim files"
}

Write-Host -ForegroundColor Green "Checking if we need to convert the wim files to vhdx files so we can boot from them"

$WinDCCoreVHDXFile = "$($WinDCCoreWimFile.Directory)\$(($WinDCCoreWimFile).Name.split(".")[0]).vhdx"
$WinDCGuiVHDXFile = "$($WinDCGuiWimFile.Directory)\$(($WinDCGuiWimFile).Name.split(".")[0]).vhdx"
$WinDCCoreVHDXFileExists = Test-Path $WinDCCoreVHDXFile
$WinDCGuiVHDXFileExists = Test-Path $WinDCGuiVHDXFile

if (!$WinDCCoreVHDXFileExists) {
    Write-Host -fore Yellow "We DO NOT have a VHDX, converting the WIM file to VHDX"
    # .-loading the convert-windowsimage script now.
    . $InstallWimLocation\Convert-WindowsImage.ps1

    Write-Host -NoNewline -Fore Yellow "Converting "; Write-Host -NoNewline -Fore Blue $WinDCCoreWimFile.FullName; Write-Host -NoNewline -Fore Yellow " to "; Write-Host -Fore Blue $WinDCCoreVHDXFile
    Convert-WindowsImage -SourcePath $WinDCCoreWimFile.FullName -VHDPath $WinDCCoreVHDXFile -DiskLayout UEFI -UnattendPath "$InstallWimLocation\unattend.xml"
    
}
elseif ((Get-ChildItem $WinDCCoreVHDXFile).LastWriteTime -lt $WinDCCoreWimFile.LastWriteTime) {
    Write-Host -fore Yellow "We have an outdated VHDX, converting the newer WIM file to VHDX"
    # .-loading the convert-windowsimage script now.
    . $InstallWimLocation\Convert-WindowsImage.ps1
    
    Write-Host -NoNewline -Fore Yellow "Converting "; Write-Host -NoNewline -Fore Blue $WinDCCoreWimFile.FullName; Write-Host -NoNewline -Fore Yellow " to "; Write-Host -Fore Blue $WinDCCoreVHDXFile
    Convert-WindowsImage -SourcePath $WinDCCoreWimFile.FullName -VHDPath $WinDCCoreVHDXFile -DiskLayout UEFI -UnattendPath "$InstallWimLocation\unattend.xml"

}

if (!$WinDCGuiVHDXFileExists) {
    Write-Host -fore Yellow "We DO NOT have a VHDX, converting the WIM file to VHDX"
    # .-loading the convert-windowsimage script now.
    . $InstallWimLocation\Convert-WindowsImage.ps1

    Write-Host -NoNewline -Fore Yellow "Converting "; Write-Host -NoNewline -Fore Blue $WinDCGuiWimFile.FullName; Write-Host -NoNewline -Fore Yellow " to "; Write-Host -Fore Blue $WinDCGuiVHDXFile
    Convert-WindowsImage -SourcePath $WinDCGuiWimFile.FullName -VHDPath $WinDCGuiVHDXFile -DiskLayout UEFI -UnattendPath "$InstallWimLocation\unattend.xml"

}

elseif ((Get-ChildItem $WinDCGuiVHDXFile).LastWriteTime -lt $WinDCGuiWimFile.LastWriteTime) {
    Write-Host -fore Yellow "We have an outdated VHDX, converting the newer WIM file to VHDX"
    # .-loading the convert-windowsimage script now.
    . $InstallWimLocation\Convert-WindowsImage.ps1

    Write-Host -NoNewline -Fore Yellow "Converting "; Write-Host -NoNewline -Fore Blue $WinDCGuiWimFile.FullName; Write-Host -NoNewline -Fore Yellow " to "; Write-Host -Fore Blue $WinDCGuiVHDXFile
    Convert-WindowsImage -SourcePath $WinDCGuiWimFile.FullName -VHDPath $WinDCGuiVHDXFile -DiskLayout UEFI -UnattendPath "$InstallWimLocation\unattend.xml"
}

Write-Host -fore Green "Done preparing the VHDX files"