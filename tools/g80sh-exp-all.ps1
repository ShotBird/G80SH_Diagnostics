# g80sh-exp-all.ps1 — 티켓 20. GPU 를 깨우는 상주 프로그램을 **전부** 멈추면 D3 에 머물러 폭풍이 멎는가.
#
# 새 가설(09-24 04:30): 깨우는 쪽이 여럿이라 하나 빼면 다른 것이 곧 깨운다(TRCC·Logitech 단독 시험 무효와 일치).
#   빈도는 "GPU 가 D3 에 들어가는 빈도"가 정하고, 깨우는 쪽을 전부 없애야 D3 에 머문다.
# 멈추는 것: TRCC 계열, CaseDisplay·LibreHardwareMonitor, RemoteDisplaySwitch 감시자, Logitech(Options+·G HUB),
#            AMD 사용자 쪽(Radeon Software 트레이·External Events·Ryzen Master SDK 메트릭 서버)
# 30분 가벼운 캡처 → 정지 상태에서 3분 정밀 캡처(남은 깨우는 쪽 명단) → 전부 복구.
# 사용자 세션·관리자 권한 임시 작업 'G80SH Exp All' (끝나면 스스로 지움). 사슬 검증용 — 해결책이 아니다.
param([int]$Min = 30)
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$d   = 'C:\dev\1_PC_Setup\_evidence\exp-all'
$log = Join-Path $d 'exp.log'
New-Item -ItemType Directory -Force $d | Out-Null
function Log($m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }

$tasks    = 'CaseDisplay', 'LibreHardwareMonitor', 'Remote Display Switch', 'AMDRyzenMasterSDKTask'
$procs    = 'TRCC', 'HWINFO', 'USBLCD', 'USBLCDNEW', 'CaseDisplay', 'LibreHardwareMonitor', 'RadeonSoftware', 'atieclxx',
            'CPUMetricsServer', 'lghub_agent', 'lghub_system_tray', 'lghub_updater',
            'logioptionsplus_agent', 'logioptionsplus_appbroker', 'logioptionsplus_updater'
$services = 'OptionsPlusUpdaterService', 'AMD External Events Utility'
function Snapshot { ((Get-Process -Name $procs -ErrorAction SilentlyContinue).Name | Sort-Object -Unique) -join ',' }

Log ("armed — running: " + (Snapshot))
foreach ($t in $tasks) { Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue }
foreach ($s in $services) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
# 감시자 powershell 은 작업 종료로 안 죽을 수 있어 명령줄로 찾아 끈다
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -match 'RemoteDisplaySwitch\.ps1' |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Stop-Process -Name $procs -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Stop-Process -Name $procs -Force -ErrorAction SilentlyContinue   # 서로 되살리는 것 대비 한 번 더
Log ("stopped — remaining: " + (Snapshot) + " / watcher: " + @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -match 'RemoteDisplaySwitch\.ps1').Count)

$etl = Join-Path $d 'g80sh-exp-off-all.etl'
& $x -start G80SHExp -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x101:5+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $etl -BufferSize 1024 -MinBuffers 64 -MaxBuffers 512 -MaxFile 4096 -FileMode Sequential 2>&1 | Out-Null
Log 'capture start'
for ($i = 0; $i -lt $Min; $i++) {
    Start-Sleep -Seconds 60
    $back = Snapshot
    if ($back) { Log "revived: $back — 다시 정지"; Stop-Process -Name $procs -Force -ErrorAction SilentlyContinue }
}
& $x -stop G80SHExp 2>&1 | Out-Null
Log ("capture stop {0:N0} bytes" -f (Get-Item $etl -ErrorAction SilentlyContinue).Length)

& 'C:\dev\1_PC_Setup\tools\g80sh-deep-capture.ps1' -Sec 180 -Tag allstop
Log 'deep census (180s) done'

foreach ($s in $services) { Start-Service -Name $s -ErrorAction SilentlyContinue }
foreach ($t in $tasks + 'TRCCAppStartup') { Start-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue }
Start-Process 'C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe' -ArgumentList 'atlogon' -ErrorAction SilentlyContinue
Start-Process 'C:\Program Files\LGHUB\system_tray\lghub_system_tray.exe' -ArgumentList '--minimized' -ErrorAction SilentlyContinue
Start-Process 'C:\Program Files\LogiOptionsPlus\logioptionsplus_agent.exe' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 30
Log ("restored — running: " + (Snapshot) + " / watcher: " + @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -match 'RemoteDisplaySwitch\.ps1').Count)
Log 'done — task unregister'
Unregister-ScheduledTask -TaskName 'G80SH Exp All' -Confirm:$false
