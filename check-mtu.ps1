$A = "Ethernet 2"

# 1. CONTROLE - propriedade inocua que o driver le do registro
Set-NetAdapterAdvancedProperty -Name $A -RegistryKeyword "DebugLevel" -RegistryValue "5"

# 2. SUJEITO - MTU da NIC pedido ABAIXO do host_mtu (1014 - 14 = MTU 1000)
Set-NetAdapterAdvancedProperty -Name $A -RegistryKeyword "*JumboPacket" -RegistryValue "1014"

# 3. VEREDITO IMEDIATO - antes mesmo do upgrade
Get-NetAdapter -Name $A | Select-Object Name, MtuSize
Get-NetAdapterAdvancedProperty -Name $A |
  Where-Object RegistryKeyword -match "Jumbo|DebugLevel" |
  Select-Object RegistryKeyword, RegistryValue



# 4. camada IP (so depois de saber o MtuSize, o IP nao pode excede-lo)
Set-NetIPInterface -InterfaceAlias $A -AddressFamily IPv4 -NlMtuBytes 1350

# 5. coletar
.\Collect-State.ps1 -Alias "Ethernet 2" -Tag antes > antes.txt

# 6. upgrade IN-PLACE (Update driver, nunca Uninstall device)

# 7. coletar de novo
.\Collect-State.ps1 -Alias "Ethernet 2" -Tag depois > depois.txt
