$domainsFile = "C:\dnstest\domains.txt"
$resultsFile = "C:\dnstest\results.csv"
$statsFile   = "C:\dnstest\stats.txt"
$resultsFileTCP = "C:\dnstest\results_tcp.csv"
$statsFileTCP   = "C:\dnstest\stats_tcp.txt"

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

if (!(Test-Path $resultsFileTCP)) {
    "Timestamp,Domain,DNS,Status,LatencyMs" | Out-File $resultsFileTCP
}

Write-Host "Start monitoringu DNS (równoległego)..."

function Test-DNS {
    param ($domain, $dns)

    $output = @()

    foreach ($mode in @("UDP","TCP")) {

        $start = Get-Date

        try {
            if ($dns -eq "system") {
                if ($mode -eq "TCP") {
                    Resolve-DnsName -Name $domain -TcpOnly -ErrorAction Stop | Out-Null
                } else {
                    Resolve-DnsName -Name $domain -ErrorAction Stop | Out-Null
                }
            } else {
                if ($mode -eq "TCP") {
                    Resolve-DnsName -Name $domain -Server $dns -TcpOnly -ErrorAction Stop | Out-Null
                } else {
                    Resolve-DnsName -Name $domain -Server $dns -ErrorAction Stop | Out-Null
                }
            }

            $latency = ((Get-Date) - $start).TotalMilliseconds
            $status = "OK"
        }
        catch {
            $latency = -1
            $status = "ERROR"
        }

        $output += [PSCustomObject]@{
            DNS = $dns
            Mode = $mode
            Status = $status
            Latency = [math]::Round($latency,2)
        }
    }

    return $output
}

function Calculate-Stats {

    $data = Get-Content $resultsFile | ConvertFrom-Csv
    $grouped = $data | Group-Object DNS

    $output = @()

    foreach ($group in $grouped) {

        $total = $group.Count
        $errors = @($group.Group | Where-Object {$_.Status -eq "ERROR"}).Count
        $ok = $total - $errors

        $latencies = @(
            $group.Group |
            Where-Object { [double]$_.LatencyMs -gt 0 } |
            ForEach-Object { [double]$_.LatencyMs }
        )

        if ($latencies.Count -gt 0) {
            $avg = [math]::Round(($latencies | Measure-Object -Average).Average,2)
            $min = ($latencies | Measure-Object -Minimum).Minimum
            $max = ($latencies | Measure-Object -Maximum).Maximum
        } else {
            $avg = 0
            $min = 0
            $max = 0
        }

        $total = $group.Count
        $uptime = if ($total -gt 0) {
            [math]::Round((($total - $errors) / $total) * 100,2)
        } else { 0 }

        $output += "DNS: $($group.Name) | avg=${avg}ms | min=${min} | max=${max} | uptime=${uptime}% ($errors/$total errors)"
    }

    $output | Out-File $statsFile

    Write-Host "`n=== STATYSTYKI ==="
    $output | ForEach-Object { Write-Host $_ }
    Write-Host "==================`n"
}

function Calculate-Stats-TCP {

    $data = Get-Content $resultsFileTCP | ConvertFrom-Csv
    $grouped = $data | Group-Object DNS

    $output = @()

    foreach ($group in $grouped) {

        $total = $group.Count
        $errors = @($group.Group | Where-Object {$_.Status -eq "ERROR"}).Count

        $latencies = @(
            $group.Group |
            Where-Object {
                $_.Status -eq "OK" -and [double]$_.LatencyMs -gt 0
            } |
            ForEach-Object { [double]$_.LatencyMs }
        )

        if ($latencies.Count -gt 0) {
            $avg = [math]::Round(($latencies | Measure-Object -Average).Average,2)
            $min = ($latencies | Measure-Object -Minimum).Minimum
            $max = ($latencies | Measure-Object -Maximum).Maximum
        } else {
            $avg = 0; $min = 0; $max = 0
        }

        $uptime = if ($total -gt 0) {
            [math]::Round((($total - $errors) / $total) * 100,2)
        } else { 0 }

        $output += "DNS: $($group.Name) | avg=${avg}ms | min=${min} | max=${max} | uptime=${uptime}% ($errors/$total errors)"
    }

    $output | Out-File $statsFileTCP
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
            if ($r.Mode -eq "UDP") {
                $line = "$timestamp,$domain,$($r.DNS),$($r.Status),$($r.Latency)"
                Add-Content $resultsFile $line
            }

            if ($r.Mode -eq "TCP") {
                $line = "$timestamp,$domain,$($r.DNS),$($r.Status),$($r.Latency)"
                Add-Content $resultsFileTCP $line
            }

            Write-Host "$domain | $($r.DNS) | $($r.Mode) | $($r.Status) | $($r.Latency)ms"
        }

    # statystyki
    Calculate-Stats
    Calculate-Stats-TCP

    Start-Sleep -Seconds 60
}