$GPORemoveConsumer = Get-GPO -Name "Remove Consumer Items" -ErrorAction SilentlyContinue

if (!$GPORemoveCloudContent) {
    New-GPO -Name "Remove Consumer Items" | `
    Set-GPRegistryValue -Key "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -ValueName DisableSoftLanding -type dWord -Value 1 | `
    Set-GPRegistryValue -Key "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -ValueName DisableWindowsConsumerFeatures -type dWord -Value 1 | `
    New-GPlink -Target "dc=Mivex,dc=lab"
}