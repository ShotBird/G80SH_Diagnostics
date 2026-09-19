# g80sh-uptime-windows.ps1 — 절전 구간에서 'PC가 꺼져 있던 시간'을 제외하고 집계한다.
#
# 566(화면 전원 전환)만으로 구간을 만들면, 그 사이에 시스템이 종료돼 있던 시간이
# 통째로 '절전'으로 잡힌다. 부팅/종료 이벤트로 가동 구간을 만들어 교집합만 센다.
#   부팅   Kernel-General 12 (운영 체제가 시작되었습니다)
#   종료   Kernel-General 13 (운영 체제가 종료됩니다)  또는 비정상 종료
param([string]$Since = '2026-09-08')
$ErrorActionPreference = 'SilentlyContinue'

$boot = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=12} -ErrorAction SilentlyContinue | Sort-Object TimeCreated)
$down = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=13} -ErrorAction SilentlyContinue | Sort-Object TimeCreated)

# 가동 구간 = 부팅 ~ 그 다음 종료(없으면 현재)
$up = @()
foreach ($b in $boot) {
    $e = ($down | Where-Object { $_.TimeCreated -gt $b.TimeCreated } | Select-Object -First 1)
    $end = if ($e) { $e.TimeCreated } else { Get-Date }
    $up += [pscustomobject]@{ S = $b.TimeCreated; E = $end }
}

$s = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=566} -ErrorAction SilentlyContinue | Sort-Object TimeCreated)
$ev = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Kernel-PnP/Device Management'; Id=1010} -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'SAM7B0C|SAM7B0B|SAM7B11|Default_Monitor' } | Sort-Object TimeCreated)

function OverlapMin($a1, $a2) {   # 절전 구간과 가동 구간의 교집합(분)
    $t = 0.0
    foreach ($u in $up) {
        $s2 = if ($a1 -gt $u.S) { $a1 } else { $u.S }
        $e2 = if ($a2 -lt $u.E) { $a2 } else { $u.E }
        if ($e2 -gt $s2) { $t += ($e2 - $s2).TotalMinutes }
    }
    return $t
}

$rows = @()
for ($i = 0; $i -lt $s.Count; $i++) {
    if ($s[$i].Message -match '(\d+)\D+(\d+)') {
        if (([int]$matches[2] % 3) -ne 1) { continue }
        $a1 = $s[$i].TimeCreated
        $a2 = if ($i + 1 -lt $s.Count) { $s[$i+1].TimeCreated } else { Get-Date }
        if ($a1 -lt (Get-Date $Since)) { continue }
        $raw = [math]::Round(($a2 - $a1).TotalMinutes, 1)
        $real = [math]::Round((OverlapMin $a1 $a2), 1)
        $n = @($ev | Where-Object { $_.TimeCreated -gt $a1.AddSeconds(3) -and $_.TimeCreated -lt $a2 }).Count
        $rows += [pscustomobject]@{ Start=$a1; Raw=$raw; Real=$real; N=$n }
    }
}

Write-Output "=== 절전 구간 (raw = 566 간격, real = PC 가동 중인 부분만) ==="
$rows | Where-Object { $_.Real -ge 5 } | ForEach-Object {
    "  {0}  raw {1,7}분  실제 {2,7}분  1010 {3,5}건  시간당 {4,6:N1}  {5}" -f `
      $_.Start.ToString('MM-dd HH:mm'), $_.Raw, $_.Real, $_.N, $(if($_.Real -gt 0){$_.N/($_.Real/60)}else{0}), $(if($_.N -eq 0){'← 0건'}else{''})
}
Write-Output ""
Write-Output "=== 일자별 (실제 절전 시간 기준) ==="
$rows | Group-Object { $_.Start.ToString('MM-dd') } | Sort-Object Name | ForEach-Object {
    $h = ($_.Group | Measure-Object Real -Sum).Sum / 60
    $n = ($_.Group | Measure-Object N -Sum).Sum
    "  {0}   실제절전 {1,6:N1}시간   1010 {2,5}건   시간당 {3,6:N1}" -f $_.Name, $h, $n, $(if ($h -gt 0.05) { $n/$h } else { 0 })
}
