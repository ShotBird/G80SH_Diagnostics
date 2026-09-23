# g80sh-exp-trcc.ps1 — 티켓 20. 단일 변수 시험: TRCC(+딸린 HWINFO)를 끄면 GPU D3→D0 복귀와 폭풍이 주는가.
#
# 19 에서 GPU 를 깨운 프로그램 중 HWINFO(= TRCC 가 센서 수집용으로 띄운 것)가 2/6 이었다.
# A 구간(켠 채) / B 구간(끈 채)을 같은 절전 안에서 연달아 잰다. 끝나면 TRCC 를 다시 띄운다.
# 사용자 세션에서 관리자 권한으로 돈다(임시 작업 'G80SH Exp TRCC', 끝나면 스스로 지움).
# 이 시험은 사슬 검증용이다 — 해결책이 아니다(맵 상시규칙 1).
param([int]$Min = 30)
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$d   = 'C:\dev\PC\_evidence\exp-trcc'
$log = Join-Path $d 'exp.log'
New-Item -ItemType Directory -Force $d | Out-Null
function Log($m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }
function Cap($name) {
    $etl = Join-Path $d "g80sh-exp-$name.etl"
    & $x -start G80SHExp -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x101:5+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $etl -BufferSize 1024 -MinBuffers 64 -MaxBuffers 512 -MaxFile 4096 -FileMode Sequential 2>&1 | Out-Null
    Log "$name start"
    Start-Sleep -Seconds ($Min * 60)
    & $x -stop G80SHExp 2>&1 | Out-Null
    Log ("$name stop {0:N0} bytes" -f (Get-Item $etl -ErrorAction SilentlyContinue).Length)
}
Log ("armed — TRCC/HWINFO running: " + ((Get-Process TRCC, HWINFO -ErrorAction SilentlyContinue | ForEach-Object Name) -join ','))
Cap 'A-trcc-on'
Stop-Process -Name TRCC, HWINFO, USBLCD, USBLCDNEW -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Log ("TRCC stopped — remaining: " + ((Get-Process TRCC, HWINFO -ErrorAction SilentlyContinue | ForEach-Object Name) -join ','))
Cap 'B-trcc-off'
Start-Process 'C:\Program Files\TRCCCAP\TRCC.exe' -WorkingDirectory 'C:\Program Files\TRCCCAP'
Start-Sleep -Seconds 20
Log ("TRCC restarted — running: " + ((Get-Process TRCC, HWINFO -ErrorAction SilentlyContinue | ForEach-Object Name) -join ','))
Log 'done — task unregister'
Unregister-ScheduledTask -TaskName 'G80SH Exp TRCC' -Confirm:$false
