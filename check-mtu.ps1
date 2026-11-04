# se reclamar de execution policy
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\Collect-State.ps1 -Tag antes > antes.txt


$Alias = "Ethernet 2"; $Tag = "antes"

"=== $Tag - $(Get-Date -Format o) ==="
Get-NetAdapter -Name $Alias | Format-List Name, ifIndex, InterfaceGuid, DriverVersion, MacAddress, MtuSize
Get-NetAdapterAdvancedProperty -Name $Alias | Select-Object DisplayName, DisplayValue, RegistryKeyword, RegistryValue | Format-Table -AutoSize
Get-NetIPInterface -InterfaceAlias $Alias -PolicyStore ActiveStore | Select-Object AddressFamily, NlMtu | Format-Table -AutoSize
Get-NetIPInterface -InterfaceAlias $Alias -PolicyStore PersistentStore -ErrorAction SilentlyContinue | Select-Object AddressFamily, NlMtu | Format-Table -AutoSize
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}" | ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } | Where-Object { $_.MatchingDeviceId -like "*ven_1af4*" } | Format-List PSChildName, NetCfgInstanceId, NetworkAddress, DebugLevel, *Jumbo*, *MTU*
$live = (Get-NetAdapter).InterfaceGuid
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" | ForEach-Object { $m = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).MTU; if ($m) { [PSCustomObject]@{ GUID=$_.PSChildName; MTU=$m; Viva=($live -contains $_.PSChildName) } } } | Format-Table -AutoSize


Set-NetAdapterAdvancedProperty -Name "Ethernet 2" -RegistryKeyword "*JumboPacket" -RegistryValue 1014
