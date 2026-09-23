# g80sh-exp-off.ps1 — 티켓 20. 단일 변수 시험: 프로그램 하나를 멈춘 채 GPU D3→D0 복귀·폭풍을 잰다.
#
# 기준선(켠 상태)은 같은 밤 TRCC 시험 A/B 구간(30분 각각, D3 68/70, 사이클 78.6/78.4 시간당)을 쓴다.
# 멈춘 동안만 캡처하고, 끝나면 되살린다. 결과 분석은 tools\g80sh-exp-analyze.ps1 -Dir <폴더>.
# 사용자 세션·관리자 권한 임시 작업 'G80SH Exp Off' 로 돈다(끝나면 스스로 지움).
# 이 시험은 사슬 검증용이다 — 해결책이 아니다(맵 상시규칙 1).
param(
    [Parameter(Mandatory)][string]$Name,         # 폴더·파일 이름 (예: logi)
    [string[]]$Procs = @(),                      # 멈출 프로세스 이름
    [string[]]$Services = @(),                   # 멈출 서비스 이름
    [string]$RestartExe = '',                    # 되살릴 실행 파일
    [int]$Min = 30
)
# -File 로 부르면 쉼표 목록이 문자열 하나로 들어온다(09-24 Logitech 시험에서 agent 가 안 멈춘 원인)
$Procs    = @($Procs    | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Services = @($Services | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$d   = "C:\dev\PC\_evidence\exp-$Name"
$log = Join-Path $d 'exp.log'
New-Item -ItemType Directory -Force $d | Out-Null
function Log($m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }
function Running { ((Get-Process -Name $Procs -ErrorAction SilentlyContinue).Name + (Get-Service -Name $Services -ErrorAction SilentlyContinue | Where-Object Status -eq Running).Name) -join ',' }

Log ("armed — running: " + (Running))
foreach ($s in $Services) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
Stop-Process -Name $Procs -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Log ("stopped — remaining: " + (Running))

$etl = Join-Path $d "g80sh-exp-off-$Name.etl"
& $x -start G80SHExp -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x101:5+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $etl -BufferSize 1024 -MinBuffers 64 -MaxBuffers 512 -MaxFile 4096 -FileMode Sequential 2>&1 | Out-Null
Log 'capture start'
Start-Sleep -Seconds ($Min * 60)
& $x -stop G80SHExp 2>&1 | Out-Null
Log ("capture stop {0:N0} bytes" -f (Get-Item $etl -ErrorAction SilentlyContinue).Length)

foreach ($s in $Services) { Start-Service -Name $s -ErrorAction SilentlyContinue }
if ($RestartExe) { Start-Process $RestartExe -WorkingDirectory (Split-Path $RestartExe) }
Start-Sleep -Seconds 20
Log ("restarted — running: " + (Running))
Log 'done — task unregister'
Unregister-ScheduledTask -TaskName 'G80SH Exp Off' -Confirm:$false
