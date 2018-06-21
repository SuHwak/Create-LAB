
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


Write-Host -fore Green "Done preparing the vSwitches"