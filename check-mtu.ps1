$A = "Ethernet 2"

# CONTROLE — propriedade inócua que o driver lê do registro.
# Se sobreviver ao upgrade, a chave de instância sobreviveu.
Set-NetAdapterAdvancedProperty -Name $A -RegistryKeyword "DebugLevel" -RegistryValue 5

# SUJEITO — MTU da NIC pedido ABAIXO do host_mtu.
# 1014 inclui o header Ethernet → MTU 1000.
Set-NetAdapterAdvancedProperty -Name $A -RegistryKeyword "*JumboPacket" -RegistryValue 1014

# veredito imediato
Get-NetAdapter -Name $A | Select-Object Name, MtuSize
Get-NetAdapterAdvancedProperty -Name $A | Where-Object RegistryKeyword -match "Jumbo|DebugLevel" |
  Select-Object RegistryKeyword, RegistryValue, DisplayValue


# se o MtuSize ficou 1400:
Set-NetIPInterface -InterfaceAlias $A -AddressFamily IPv4 -NlMtuBytes 1350

# se ficou 1000, use um valor abaixo disso (IPv4 aceita a partir de 576):
# Set-NetIPInterface -InterfaceAlias $A -AddressFamily IPv4 -NlMtuBytes 950


param([string]$Alias = "Ethernet 2", [string]$Tag = "antes")

"=== $Tag — $(Get-Date -Format o) ==="

Get-NetAdapter -Name $Alias |
  Format-List Name, ifIndex, InterfaceGuid, DriverVersion, DriverDate, MacAddress, MtuSize

"--- propriedades avançadas ---"
Get-NetAdapterAdvancedProperty -Name $Alias |
  Select-Object DisplayName, DisplayValue, RegistryKeyword, RegistryValue | Format-Table -Auto

"--- NlMtu ActiveStore ---"
Get-NetIPInterface -InterfaceAlias $Alias -PolicyStore ActiveStore |
  Select-Object AddressFamily, NlMtu | Format-Table -Auto

"--- NlMtu PersistentStore ---"
Get-NetIPInterface -InterfaceAlias $Alias -PolicyStore PersistentStore -ErrorAction SilentlyContinue |
  Select-Object AddressFamily, NlMtu | Format-Table -Auto

"--- chave de instância do device ---"
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}" |
  ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
  Where-Object { $_.MatchingDeviceId -like "*ven_1af4*" } |
  Format-List PSChildName, NetCfgInstanceId, MatchingDeviceId, NetworkAddress, DebugLevel, *Jumbo*, *MTU*

"--- chaves de IP (orfas aparecem com Viva=False) ---"
$live = (Get-NetAdapter).InterfaceGuid
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" | ForEach-Object {
    $m = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).MTU
    if ($m) { [PSCustomObject]@{ GUID = $_.PSChildName; MTU = $m; Viva = ($live -contains $_.PSChildName) } }
} | Format-Table -Auto
