# g80sh-daily-rate.ps1 — 일자별 발생률(실제 절전 시간 기준)을 매일 한 번 로그에 남긴다.
#
# 09-22 부터 발생률이 두 배가 됐다(81.5 → 136.9 → 155.8/h, 티켓 16). 계속 악화되는지가 제출 근거다.
# g80sh-uptime-windows.ps1 의 "일자별" 표만 잘라 _evidence\daily-rate.log 에 누적한다.
# 작업 스케줄러 'G80SH Daily Rate' (사용자 권한, 매일 23:55).
$log = 'C:\dev\PC\_evidence\daily-rate.log'
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\dev\PC\tools\g80sh-uptime-windows.ps1' 2>&1 | Out-String
$i = $out.IndexOf('=== 일자별')
$body = if ($i -ge 0) { $out.Substring($i) } else { $out }
Add-Content -LiteralPath $log -Value ("##### {0}`r`n{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $body.TrimEnd()) -Encoding UTF8
