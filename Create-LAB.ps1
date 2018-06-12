# Assuming Set-ExecutionPolicy RemoteSigned

# Loading Modules
# . "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\Get-FileName.ps1"
# . "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\Convert-WindowsImage.ps1"

# Setting Variables

$domainController = "MivexLab-DC1"
$domainName = "MIVEX.LAB"
$memberServersCount = 2
$ISOlocation = $null
$ethernet = Get-NetAdapter -Name Ethernet
$wifi = Get-NetAdapter -Name Wi-Fi

# Set Administrator Password

$adminUsername = "Administrator"
$adminPassword = "Passw0rd" 
$adminSecPassword = $adminPassword | ConvertTo-SecureString -AsPlainText -Force

$secstr = New-Object -TypeName System.Security.SecureString
$adminPassword.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $adminUsername, $secstr

if (!$ISOlocation)
    {

    $ISOLocation = Read-Host -prompt "Please provide the path to the ISO file."

    }

$mountResult = Mount-DiskImage -ImagePath "C:\Users\m.vermeer\Downloads\ISO\Windows Server 2016.ISO" -PassThru

$driveLetter = ($mountResult | Get-Volume).DriveLetter + ":"

If (! (Test-Path $destination)) { mkdir $destination }
Set-Location $destination