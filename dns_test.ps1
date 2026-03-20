$domainsFile = "C:\dnstest\domains.txt"
$resultsFile = "C:\dnstest\results.csv"
$statsFile   = "C:\dnstest\stats.txt"

$dnsServers = @(
    "system",
    "8.8.8.8",
    "8.8.4.4",
    "1.1.1.1",
    "1.0.0.1"
)

$domains = Get-Content $domainsFile

if (!(Test-Path $resultsFile)) {
    "Timestamp,Domain,DNS,Status,LatencyMs" | Out-File $resultsFile
}

Write-Host "Start monitoringu DNS (równoległego)..."

function Test-DNS {
    param ($domain, $dns)

    $start = Get-Date

    try {
        if ($dns -eq "system") {
            Resolve-DnsName -Name $domain -ErrorAction Stop | Out-Null
        } else {
            Resolve-DnsName -Name $domain -Server $dns -ErrorAction Stop | Out-Null
        }

        $latency = ((Get-Date) - $start).TotalMilliseconds
        $status = "OK"
    }
    catch {
        $latency = -1
        $status = "ERROR"
    }

    return [PSCustomObject]@{
        DNS = $dns
        Status = $status
        Latency = [math]::Round($latency,2)
    }
}

function Calculate-Stats {

    $data = Get-Content $resultsFile | ConvertFrom-Csv
    $grouped = $data | Group-Object DNS

    $output = @()

    foreach ($group in $grouped) {

        $total = $group.Count
        $errors = @($group.Group | Where-Object {$_.Status -eq "ERROR"}).Count
        $ok = $total - $errors

        $latencies = $group.Group | Where-Object {$_.LatencyMs -gt 0} | Select-Object -ExpandProperty LatencyMs

        $avg = if ($latencies.Count -gt 0) {
            [math]::Round(($latencies | Measure-Object -Average).Average,2)
        } else { 0 }

        $min = if ($latencies.Count -gt 0) {
            ($latencies | Measure-Object -Minimum).Minimum
        } else { 0 }

        $max = if ($latencies.Count -gt 0) {
            ($latencies | Measure-Object -Maximum).Maximum
        } else { 0 }

        $uptime = if ($total -gt 0) {
            [math]::Round(($ok / $total) * 100,2)
        } else { 0 }

        $output += "DNS: $($group.Name) | avg=${avg}ms | min=${min} | max=${max} | uptime=${uptime}% ($errors/$total errors)"
    }

    $output | Out-File $statsFile

    Write-Host "`n=== STATYSTYKI ==="
    $output | ForEach-Object { Write-Host $_ }
    Write-Host "==================`n"
}

while ($true) {

    $domain = Get-Random -InputObject $domains
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # 🔥 równoległe uruchomienie
    $jobs = @()

    foreach ($dns in $dnsServers) {
        $jobs += Start-Job -ScriptBlock ${function:Test-DNS} -ArgumentList $domain, $dns
    }

    $results = $jobs | Wait-Job | Receive-Job

    # sprzątanie jobów
    $jobs | Remove-Job

    foreach ($r in $results) {
        $line = "$timestamp,$domain,$($r.DNS),$($r.Status),$($r.Latency)"
        Add-Content $resultsFile $line

        Write-Host "$domain | $($r.DNS) | $($r.Status) | $($r.Latency)ms"
    }

    # statystyki
    Calculate-Stats

    Start-Sleep -Seconds 120
}