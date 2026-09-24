# g80sh-daily-rate.ps1 — 일자별 발생률(실제 절전 시간 기준)을 매일 한 번 로그에 남긴다.
#
# 두 숫자를 같이 남긴다:
#   합산    g80sh-uptime-windows.ps1 의 1010 (SAM7B0C + Default_Monitor 등) — 기존 지표
#   사이클  SAM7B0C 제거만 = 폭풍 사이클 수
# ⚠ 09-20 17:04 포트 교체 이후 거의 모든 사이클이 Default_Monitor 를 거쳐 1010 이 사이클당 2건이 됐다.
#   "09-22 부터 두 배"는 대부분 이 집계 착시였다(티켓 20). 추이 판정은 **사이클** 열로 할 것.
# 작업 스케줄러 'G80SH Daily Rate' (사용자 권한, 매일 23:55).
$log = 'C:\dev\1_PC_Setup\_evidence\daily-rate.log'
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\dev\1_PC_Setup\tools\g80sh-uptime-windows.ps1' 2>&1 | Out-String
$i = $out.IndexOf('=== 일자별')
$body = if ($i -ge 0) { $out.Substring($i) } else { $out }

$hours = @{}
foreach ($l in ($body -split "`r?`n")) {
    if ($l -match '^\s+(\d\d-\d\d)\s+실제절전\s+([\d.]+)시간') { $hours[$matches[1]] = [double]$matches[2] }
}
$ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Device Management'; Id = 1010 } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'SAM7B0C' })
$cyc = $ev | Group-Object { $_.TimeCreated.ToString('MM-dd') } | Sort-Object Name | ForEach-Object {
    $h = $hours[$_.Name]
    "  {0}   사이클 {1,5}건   시간당 {2,6:N1}" -f $_.Name, $_.Count, $(if ($h -gt 0.05) { $_.Count / $h } else { 0 })
}
Add-Content -LiteralPath $log -Value ("##### {0}`r`n{1}`r`n=== 사이클 (SAM7B0C 제거만, 같은 절전 시간) ===`r`n{2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $body.TrimEnd(), ($cyc -join "`r`n")) -Encoding UTF8
