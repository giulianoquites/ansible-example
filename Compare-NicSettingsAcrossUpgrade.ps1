<#
.SYNOPSIS
    Captura e compara TODAS as configuracoes de uma NIC antes e depois de um
    upgrade de driver, para provar o que sobrevive e o que e perdido.

.DESCRIPTION
    Responde a pergunta do mantenedor na issue #1722: "we need to check that all
    the NIC settings are saved and recovered after upgrade".

    O script captura tres camadas independentes, que sao perdidas por motivos
    diferentes e precisam ser separadas no diagnostico:

      1. CHAVE DE INSTANCIA DO DEVICE (miniport NDIS)
         HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-...}\<NNNN>
         Guarda *JumboPacket e todas as advanced properties do INF.
         Perdida se o upgrade remover o device em vez de atualizar no lugar.

      2. CONFIG DA CAMADA IP (stack TCP/IP, independente do miniport)
         HKLM\SYSTEM\CurrentControlSet\Services\Tcpip{,6}\Parameters\Interfaces\{GUID}
         Guarda a MTU setada via "netsh interface ipv4 set subinterface",
         IP estatico, DNS. Indexada pelo GUID DA INTERFACE - se o
         NetCfgInstanceId mudar, tudo isso vira orfao de uma vez.

      3. MTU EFETIVA NEGOCIADA (runtime)
         MtuSize do NDIS e NlMtu do IP. Mesmo com (1) e (2) preservados, o
         NetKVM sobrescreve nMaxDataSize com o host_mtu em todo boot - esse e
         o problema da ISSUE-1, que NAO e especifico de upgrade.

    A comparacao das tres em conjunto diz qual mecanismo esta agindo:

      *JumboPacket mudou .................. chave de instancia foi recriada
      GUID mudou .......................... config de camada IP foi orfanada
      ambos iguais, MtuSize = host_mtu .... sobrescrita incondicional (ISSUE-1)

.PARAMETER Mode
    Snapshot : captura o estado atual e grava um JSON.
    Compare  : compara dois JSONs e imprime as diferencas.

.PARAMETER Name
    Nome do adaptador (Snapshot). Se omitido, captura todos os adaptadores
    cuja InterfaceDescription contenha "VirtIO" ou "Red Hat".

.PARAMETER Path
    Snapshot : caminho do JSON a gravar. Default: .\nic-<modo>-<timestamp>.json
    Compare  : nao usado, veja -Before / -After.

.PARAMETER Before
    Compare : JSON capturado antes do upgrade.

.PARAMETER After
    Compare : JSON capturado depois do upgrade.

.EXAMPLE
    # antes do upgrade
    .\Compare-NicSettingsAcrossUpgrade.ps1 -Mode Snapshot -Path before.json

.EXAMPLE
    # depois do upgrade
    .\Compare-NicSettingsAcrossUpgrade.ps1 -Mode Snapshot -Path after.json
    .\Compare-NicSettingsAcrossUpgrade.ps1 -Mode Compare -Before before.json -After after.json

.NOTES
    Precisa de PowerShell elevado para ler as chaves de registry.
    Testado em Windows Server 2022 / 2025.
#>
[CmdletBinding(DefaultParameterSetName = 'Snapshot')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Snapshot', 'Compare')]
    [string]$Mode,

    [Parameter(ParameterSetName = 'Snapshot')]
    [string]$Name,

    [Parameter(ParameterSetName = 'Snapshot')]
    [string]$Path,

    [Parameter(ParameterSetName = 'Compare')]
    [string]$Before,

    [Parameter(ParameterSetName = 'Compare')]
    [string]$After
)

$ErrorActionPreference = 'Stop'

$NET_CLASS_GUID = '{4d36e972-e325-11ce-bfc1-08002be10318}'
$CLASS_ROOT     = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$NET_CLASS_GUID"

function Get-RegValues
{
    param([string]$KeyPath)

    if (-not (Test-Path $KeyPath))
    {
        return $null
    }

    $props = Get-ItemProperty -Path $KeyPath
    $out = [ordered]@{}
    foreach ($p in $props.PSObject.Properties)
    {
        if ($p.Name -like 'PS*')
        {
            continue
        }
        $out[$p.Name] = "$($p.Value)"
    }
    return $out
}

function Find-ClassInstanceKey
{
    param([string]$InterfaceGuid)

    Get-ChildItem -Path $CLASS_ROOT -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^\d{4}$' } |
        Where-Object {
            $v = Get-ItemProperty -Path $_.PSPath -Name NetCfgInstanceId -ErrorAction SilentlyContinue
            $v -and $v.NetCfgInstanceId -eq $InterfaceGuid
        } |
        Select-Object -First 1
}

function New-AdapterSnapshot
{
    param($Adapter)

    $guid = $Adapter.InterfaceGuid
    $snap = [ordered]@{}

    # --- identidade -------------------------------------------------------
    $snap.Identity = [ordered]@{
        Name                 = $Adapter.Name
        InterfaceDescription = $Adapter.InterfaceDescription
        InterfaceGuid        = $guid
        InterfaceIndex       = $Adapter.ifIndex
        MacAddress           = $Adapter.MacAddress
        PnPDeviceID          = $Adapter.PnPDeviceID
        Status               = "$($Adapter.Status)"
    }

    # --- driver -----------------------------------------------------------
    $snap.Driver = [ordered]@{
        DriverVersion      = $Adapter.DriverVersion
        DriverDate         = "$($Adapter.DriverDate)"
        DriverProvider     = $Adapter.DriverProvider
        DriverFileName     = $Adapter.DriverFileName
        DriverInformation  = $Adapter.DriverInformation
        DriverDescription  = $Adapter.DriverDescription
    }

    # --- camada 3: MTU efetiva em runtime ---------------------------------
    $snap.EffectiveMtu = [ordered]@{
        NdisMtuSize = $Adapter.MtuSize
    }
    foreach ($af in 'IPv4', 'IPv6')
    {
        try
        {
            $ipif = Get-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily $af -ErrorAction Stop
            $snap.EffectiveMtu["NlMtu_$af"] = $ipif.NlMtu
        }
        catch
        {
            $snap.EffectiveMtu["NlMtu_$af"] = '<indisponivel>'
        }
    }

    # --- camada 1: chave de instancia do device ---------------------------
    $classKey = Find-ClassInstanceKey -InterfaceGuid $guid
    if ($classKey)
    {
        $snap.ClassInstanceKeyPath = $classKey.PSChildName
        $snap.ClassInstanceValues  = Get-RegValues -KeyPath $classKey.PSPath
    }
    else
    {
        $snap.ClassInstanceKeyPath = '<nao encontrada>'
        $snap.ClassInstanceValues  = @{}
    }

    # --- advanced properties pela API do NDIS -----------------------------
    $adv = [ordered]@{}
    try
    {
        Get-NetAdapterAdvancedProperty -Name $Adapter.Name -AllProperties -ErrorAction Stop |
            Sort-Object RegistryKeyword |
            ForEach-Object { $adv[$_.RegistryKeyword] = "$($_.RegistryValue)" }
    }
    catch
    {
        $adv['<erro>'] = $_.Exception.Message
    }
    $snap.AdvancedProperties = $adv

    # --- camada 2: config da camada IP, indexada pelo GUID ----------------
    $snap.TcpipInterface = [ordered]@{
        IPv4 = Get-RegValues -KeyPath "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        IPv6 = Get-RegValues -KeyPath "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$guid"
    }

    # --- outras configs que o mantenedor chamou de "all NIC settings" -----
    try
    {
        $snap.IPAddresses = @(
            Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -ErrorAction Stop |
                ForEach-Object { "$($_.AddressFamily)/$($_.IPAddress)/$($_.PrefixLength)/$($_.PrefixOrigin)" }
        )
    }
    catch { $snap.IPAddresses = @() }

    try
    {
        $snap.DnsServers = @(
            (Get-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ErrorAction Stop).ServerAddresses
        )
    }
    catch { $snap.DnsServers = @() }

    try
    {
        $b = [ordered]@{}
        Get-NetAdapterBinding -Name $Adapter.Name -ErrorAction Stop |
            Sort-Object ComponentID |
            ForEach-Object { $b[$_.ComponentID] = $_.Enabled }
        $snap.Bindings = $b
    }
    catch { $snap.Bindings = @{} }

    foreach ($pair in @(
            @{ Key = 'Rss';      Cmd = { Get-NetAdapterRss      -Name $Adapter.Name -ErrorAction Stop } },
            @{ Key = 'Offloads'; Cmd = { Get-NetAdapterChecksumOffload -Name $Adapter.Name -ErrorAction Stop } },
            @{ Key = 'Lso';      Cmd = { Get-NetAdapterLso      -Name $Adapter.Name -ErrorAction Stop } },
            @{ Key = 'Power';    Cmd = { Get-NetAdapterPowerManagement -Name $Adapter.Name -ErrorAction Stop } }
        ))
    {
        try
        {
            $o = & $pair.Cmd
            $h = [ordered]@{}
            foreach ($p in $o.PSObject.Properties)
            {
                if ($p.Name -like 'PS*' -or $p.Name -eq 'CimClass' -or $p.Name -eq 'CimInstanceProperties' -or $p.Name -eq 'CimSystemProperties')
                {
                    continue
                }
                $h[$p.Name] = "$($p.Value)"
            }
            $snap[$pair.Key] = $h
        }
        catch { $snap[$pair.Key] = @{ '<indisponivel>' = $_.Exception.Message } }
    }

    return $snap
}

function Invoke-Snapshot
{
    $adapters = if ($Name)
    {
        Get-NetAdapter -Name $Name
    }
    else
    {
        Get-NetAdapter | Where-Object {
            $_.InterfaceDescription -match 'VirtIO|Red Hat'
        }
    }

    if (-not $adapters)
    {
        throw 'Nenhum adaptador encontrado. Use -Name para apontar um explicitamente.'
    }

    $result = [ordered]@{
        CapturedAt    = (Get-Date).ToString('o')
        ComputerName  = $env:COMPUTERNAME
        OSBuild       = (Get-CimInstance Win32_OperatingSystem).BuildNumber
        Adapters      = [ordered]@{}
    }

    # pnputil: quais INFs de rede estao no driver store
    try
    {
        $result.NetworkInfs = @(
            (pnputil /enum-drivers) -split "`r?`n" |
                Select-String -Pattern 'oem\d+\.inf|Original Name|Class Name|Driver Version' |
                ForEach-Object { $_.Line.Trim() }
        )
    }
    catch { $result.NetworkInfs = @() }

    foreach ($a in $adapters)
    {
        Write-Host "Capturando: $($a.Name) - $($a.InterfaceDescription)" -ForegroundColor Cyan
        $result.Adapters[$a.Name] = New-AdapterSnapshot -Adapter $a
    }

    $outPath = if ($Path) { $Path } else { ".\nic-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss').json" }
    $result | ConvertTo-Json -Depth 8 | Set-Content -Path $outPath -Encoding UTF8

    Write-Host ""
    Write-Host "Snapshot gravado em: $outPath" -ForegroundColor Green
    Write-Host "Adaptadores capturados: $($result.Adapters.Keys -join ', ')"
}

function ConvertTo-FlatMap
{
    param($Object, [string]$Prefix = '')

    $flat = @{}

    if ($null -eq $Object)
    {
        $flat[$Prefix] = '<null>'
        return $flat
    }

    if ($Object -is [System.Management.Automation.PSCustomObject])
    {
        foreach ($p in $Object.PSObject.Properties)
        {
            $key = if ($Prefix) { "$Prefix.$($p.Name)" } else { $p.Name }
            foreach ($kv in (ConvertTo-FlatMap -Object $p.Value -Prefix $key).GetEnumerator())
            {
                $flat[$kv.Key] = $kv.Value
            }
        }
        return $flat
    }

    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string])
    {
        $i = 0
        foreach ($item in $Object)
        {
            foreach ($kv in (ConvertTo-FlatMap -Object $item -Prefix "$Prefix[$i]").GetEnumerator())
            {
                $flat[$kv.Key] = $kv.Value
            }
            $i++
        }
        if ($i -eq 0) { $flat[$Prefix] = '<vazio>' }
        return $flat
    }

    $flat[$Prefix] = "$Object"
    return $flat
}

function Invoke-Compare
{
    if (-not (Test-Path $Before)) { throw "Nao encontrei: $Before" }
    if (-not (Test-Path $After))  { throw "Nao encontrei: $After" }

    $b = Get-Content $Before -Raw | ConvertFrom-Json
    $a = Get-Content $After  -Raw | ConvertFrom-Json

    $flatB = ConvertTo-FlatMap -Object $b
    $flatA = ConvertTo-FlatMap -Object $a

    $keys = ($flatB.Keys + $flatA.Keys) | Sort-Object -Unique
    $diffs = @()

    foreach ($k in $keys)
    {
        if ($k -match '^CapturedAt') { continue }

        $vb = if ($flatB.ContainsKey($k)) { $flatB[$k] } else { '<ausente>' }
        $va = if ($flatA.ContainsKey($k)) { $flatA[$k] } else { '<ausente>' }

        if ($vb -ne $va)
        {
            $diffs += [pscustomobject]@{
                Setting = $k
                Before  = $vb
                After   = $va
            }
        }
    }

    Write-Host ""
    Write-Host "=== DIFERENCAS ($($diffs.Count)) ===" -ForegroundColor Yellow
    if ($diffs.Count -eq 0)
    {
        Write-Host "Nenhuma. Todas as configuracoes sobreviveram ao upgrade." -ForegroundColor Green
    }
    else
    {
        $diffs | Format-Table -AutoSize -Wrap
    }

    # --- veredito por mecanismo ------------------------------------------
    Write-Host ""
    Write-Host "=== VEREDITO ===" -ForegroundColor Yellow

    $guidChanged   = $diffs | Where-Object { $_.Setting -match 'InterfaceGuid$' }
    $jumboChanged  = $diffs | Where-Object { $_.Setting -match '\*?JumboPacket$' }
    $classChanged  = $diffs | Where-Object { $_.Setting -match 'ClassInstanceKeyPath$' }
    $tcpipLost     = $diffs | Where-Object { $_.Setting -match 'TcpipInterface' -and $_.After -eq '<ausente>' }
    $mtuChanged    = $diffs | Where-Object { $_.Setting -match 'NdisMtuSize$|NlMtu_' }

    if ($guidChanged)
    {
        Write-Host "[M3] GUID da interface MUDOU. Toda config de camada IP (netsh MTU," -ForegroundColor Red
        Write-Host "     IP estatico, DNS) foi orfanada. O upgrade removeu e re-adicionou o device."
        $guidChanged | Format-Table -AutoSize
    }
    if ($classChanged -or $jumboChanged)
    {
        Write-Host "[M1] A chave de instancia do device foi recriada - *JumboPacket voltou" -ForegroundColor Red
        Write-Host "     ao default do INF. Confirma a hipotese do mantenedor."
    }
    if ($tcpipLost)
    {
        Write-Host "[M3] Valores sob Tcpip\Parameters\Interfaces desapareceram ($($tcpipLost.Count) chaves)." -ForegroundColor Red
    }
    if (-not $guidChanged -and -not $jumboChanged -and -not $classChanged -and $mtuChanged)
    {
        Write-Host "[M2] A config persistiu mas a MTU efetiva mudou mesmo assim." -ForegroundColor Red
        Write-Host "     Isso NAO e perda de configuracao - e a sobrescrita incondicional do"
        Write-Host "     host_mtu em InitializeMaxMTUConfig(). Ver ISSUE-1."
        $mtuChanged | Format-Table -AutoSize
    }
    if (-not $guidChanged -and -not $jumboChanged -and -not $classChanged -and -not $mtuChanged)
    {
        Write-Host "Nenhum dos tres mecanismos disparou neste cenario." -ForegroundColor Green
    }
}

switch ($Mode)
{
    'Snapshot' { Invoke-Snapshot }
    'Compare'  { Invoke-Compare }
}
