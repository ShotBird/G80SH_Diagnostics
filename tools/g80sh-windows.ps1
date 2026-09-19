# g80sh-windows.ps1 — 절전 구간(Kernel-Power 566)별 1010 발생 집계
#
# 단일 구간 관측으로는 어떤 조치도 판정할 수 없다. 30분 절전에 0건이 나올 확률이
# 원래 45% 이기 때문이다(09-19 실측: 30분 이상 구간 33개 중 15개가 0건).
# 조치 효과는 반드시 **며칠 단위 발생률**로 비교한다.
#
#   powershell -File g80sh-windows.ps1              전체
#   powershell -File g80sh-windows.ps1 -MinMin 30   30분 이상 구간만
param([double]$MinMin = 10, [string]$Since = '2026-09-08')
$ErrorActionPreference = 'SilentlyContinue'

$s = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=566} -ErrorAction SilentlyContinue | Sort-Object TimeCreated)
$ev = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Kernel-PnP/Device Management'; Id=1010} -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'SAM7B0C|SAM7B0B|SAM7B11|Default_Monitor' } | Sort-Object TimeCreated)

Write-Output ("566 전환 {0}건 / 대상 1010 {1}건" -f $s.Count, $ev.Count)
Write-Output ""

$win = @()
for ($i = 0; $i -lt $s.Count; $i++) {
    if ($s[$i].Message -match '(\d+)\D+(\d+)') {
        if (([int]$matches[2] % 3) -ne 1) { continue }   # 홀수 전환 = 꺼짐
        $start = $s[$i].TimeCreated
        $end = if ($i + 1 -lt $s.Count) { $s[$i+1].TimeCreated } else { Get-Date }
        $min = [math]::Round(($end - $start).TotalSeconds / 60, 1)
        $n = @($ev | Where-Object { $_.TimeCreated -gt $start.AddSeconds(3) -and $_.TimeCreated -lt $end }).Count
        $win += [pscustomobject]@{
            Start = $start; Min = $min; N = $n
            PerHr = if ($min -gt 0) { [math]::Round($n / ($min/60), 1) } else { 0 }
        }
    }
}

$f = $win | Where-Object { $_.Start -ge (Get-Date $Since) -and $_.Min -ge $MinMin } | Sort-Object Start
Write-Output ("=== {0} 이후 절전 구간 ({1}분 이상) ===" -f $Since, $MinMin)
$f | ForEach-Object {
    "  {0}  {1,7} 분   1010 {2,5}건   시간당 {3,6}   {4}" -f `
        $_.Start.ToString('MM-dd HH:mm'), $_.Min, $_.N, $_.PerHr, $(if ($_.N -eq 0) { '← 0건' } else { '' })
}

Write-Output ""
Write-Output "=== 요약 ==="
"  구간 수        : {0}" -f $f.Count
"  0건 구간       : {0}  ({1:N0}%)" -f @($f | Where-Object { $_.N -eq 0 }).Count, (100 * @($f | Where-Object { $_.N -eq 0 }).Count / [math]::Max(1,$f.Count))
"  총 절전 시간   : {0:N1} 시간" -f (($f | Measure-Object Min -Sum).Sum / 60)
"  총 1010        : {0}" -f ($f | Measure-Object N -Sum).Sum
"  전체 평균      : 시간당 {0:N1}건" -f ((($f | Measure-Object N -Sum).Sum) / [math]::Max(0.1, (($f | Measure-Object Min -Sum).Sum / 60)))

Write-Output ""
Write-Output "=== 일자별 (절전 시간 대비 발생률) ==="
$f | Group-Object { $_.Start.ToString('MM-dd') } | Sort-Object Name | ForEach-Object {
    $h = ($_.Group | Measure-Object Min -Sum).Sum / 60
    $n = ($_.Group | Measure-Object N -Sum).Sum
    "  {0}   절전 {1,6:N1}시간   1010 {2,5}건   시간당 {3,6:N1}" -f $_.Name, $h, $n, $(if ($h -gt 0) { $n/$h } else { 0 })
}
