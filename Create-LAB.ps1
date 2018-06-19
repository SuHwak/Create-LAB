# Assuming Set-ExecutionPolicy RemoteSigned

# Loading Modules
. "C:\Users\mverm\OneDrive\Tools\PowerShell Scripts and Commandlets\LAB\Get-FileName.ps1"

# Setting Variables

$domainController = "MivexLab-DC1"
$domainName = "MIVEX.LAB"
$memberServersCount = 2


$LabSwitches = @()

# Set Administrator Password

$adminUsername = "Administrator"
$adminPassword = "Passw0rd" 
$adminSecPassword = $adminPassword | ConvertTo-SecureString -AsPlainText -Force

$secstr = New-Object -TypeName System.Security.SecureString
$adminPassword.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $adminUsername, $secstr


