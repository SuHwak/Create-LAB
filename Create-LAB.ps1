# Assuming Set-ExecutionPolicy RemoteSigned

# Loading Modules
. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\Get-FileName.ps1"
. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\Convert-WindowsImage.ps1"

# Setting Variables

$domainController = "MivexLab-DC1"
$memberServersCount = 2
$ISOlocation = $null
$ethernet = Get-NetAdapter -Name Ethernet
$wifi = Get-NetAdapter -Name Wi-Fi

# Set Administrator Password

$adminUsername = "Administrator"
$adminPassword = "Passw0rd"
$adminPasswordNano = ConvertTo-SecureString -String $adminPassword -AsPlainText -Force 

$secstr = New-Object -TypeName System.Security.SecureString
$adminPassword.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $adminUsername, $secstr

if (!$ISOlocation)
    {

    $ISOlocation = Get-FileName -initialDirectory "G:\ISO's" -FileType "ISO"

    While ($ISOlocation -notlike ".iso")
        {

        $msgBoxInput =  [System.Windows.MessageBox]::Show('Selected file is not an ISO','Invalid File','OkCancel','Error')
        switch  ($msgBoxInput) 
            {

            'OK' 
                {

                ## Do something 

                }

            'Cancel' 
                {

                # Without the ISO we can't continue
                break

                }

            }

        }

    }

$mountResult = Mount-DiskImage -ImagePath "C:\Users\m.vermeer\Downloads\ISO\Windows Server 2016.ISO" -PassThru

$driveLetter = ($mountResult | Get-Volume).DriveLetter + ":"

If (! (Test-Path $destination)) { mkdir $destination }
Set-Location $destination