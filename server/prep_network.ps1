# Runs elevated (UAC). Prepares the PC for port forwarding:
#   1. Makes 192.168.100.51 a permanent (static) address so the
#      forwarding rule never breaks after a DHCP change.
#   2. Opens firewall ports 8000 (API) and 9000 (images).
# Result is written to logs\network_prep.log.
Start-Transcript -Path 'C:\Users\user\Desktop\Project\server\logs\network_prep.log' -Force | Out-Null
$ErrorActionPreference = 'Continue'

$cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
$ifIdx = $cfg.InterfaceIndex
$alias = $cfg.InterfaceAlias
$ip = $cfg.IPv4Address.IPAddress
$prefix = $cfg.IPv4Address.PrefixLength
$gw = $cfg.IPv4DefaultGateway.NextHop
$dns = (Get-DnsClientServerAddress -InterfaceIndex $ifIdx -AddressFamily IPv4).ServerAddresses

Write-Host "interface : $alias (index $ifIdx)"
Write-Host "address   : $ip/$prefix  gateway $gw  dns $($dns -join ', ')"

$octets = 0..3 | ForEach-Object { $bits = [Math]::Min(8, [Math]::Max(0, $prefix - $_ * 8)); if ($bits -le 0) { 0 } else { [int][Math]::Pow(2, 8 - $bits) * -1 + 256 } }
$mask = $octets -join '.'
Write-Host "netmask   : $mask"

if ((Get-NetIPInterface -InterfaceIndex $ifIdx -AddressFamily IPv4).Dhcp -eq 'Enabled') {
    Write-Host 'setting static address...'
    netsh interface ipv4 set address name="$alias" static $ip $mask $gw
    $d1 = $dns[0]; $d2 = $dns[1]
    netsh interface ipv4 set dnsservers name="$alias" static $d1 validate=no
    if ($d2) {
        netsh interface ipv4 add dnsservers name="$alias" $d2 index=2 validate=no
    }
} else {
    Write-Host 'address already static - skipped'
}

Start-Sleep -Seconds 2
$newIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4Address.IPAddress
Write-Host "address now: $newIp"

if (-not (Get-NetFirewallRule -DisplayName 'CCTV API (TCP 8000)' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'CCTV API (TCP 8000)' -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Any | Out-Null
    Write-Host 'firewall rule added: 8000'
} else { Write-Host 'firewall rule exists: 8000' }

if (-not (Get-NetFirewallRule -DisplayName 'CCTV images (TCP 9000)' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'CCTV images (TCP 9000)' -Direction Inbound -Protocol TCP -LocalPort 9000 -Action Allow -Profile Any | Out-Null
    Write-Host 'firewall rule added: 9000'
} else { Write-Host 'firewall rule exists: 9000' }

try {
    $h = Invoke-WebRequest -Uri 'http://localhost:8000/health' -UseBasicParsing -TimeoutSec 5
    Write-Host "backend still healthy: $($h.Content)"
} catch {
    Write-Host "backend health check failed: $($_.Exception.Message)"
}

Stop-Transcript | Out-Null
