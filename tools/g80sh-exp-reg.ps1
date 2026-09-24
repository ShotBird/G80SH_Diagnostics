# g80sh-exp-reg.ps1 — 티켓 20. AMD 드라이버 레지스트리 값 하나를 바꿔 GPU 를 재시작하고 폭풍의 시간 구조를 잰다.
#
# 가설 H-ULPS: 18 의 "재연결 후 약 32초 경계"는 모니터 내부 타이머가 아니라
#   AMD PP_ULPSDelayIntervalInMilliSeconds(현재 30000 = 30초)다. 값을 바꾸면 경계가 따라 움직여야 한다.
# 순서: 원래 값 백업 → 새 값 → GPU 재시작 → (화면 꺼짐 60초로 임시 단축) → $Min 분 캡처 → 원복 → GPU 재시작.
# 원복은 finally 에서 반드시 한다. 사용자 세션·관리자 권한 임시 작업 'G80SH Exp Reg'.
# 사슬 검증용 — 해결책이 아니다(맵 상시규칙 1).
param(
    [Parameter(Mandatory)][string]$Value,      # 레지스트리 값 이름
    [Parameter(Mandatory)][int]$Data,          # 시험 값
    [string]$Tag = 'reg',
    [int]$Min = 30
)
$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000'
$gpu = 'PCI\VEN_1002&DEV_7550&SUBSYS_E4891DA2&REV_C0\6&8916a45&0&00000009'
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$d   = "C:\dev\1_PC_Setup\_evidence\exp-$Tag"
$log = Join-Path $d 'exp.log'
New-Item -ItemType Directory -Force $d | Out-Null
function Log($m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }
function Restart-Gpu {
    $r = pnputil /restart-device "$gpu" 2>&1
    Log ("GPU restart: " + (($r | Select-Object -Last 2) -join ' '))
    Start-Sleep -Seconds 20
    Log ("monitors: " + ((Get-PnpDevice -Class Monitor -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { ($_.InstanceId -split '\\')[1] }) -join ','))
}
$orig = (Get-ItemProperty $key -Name $Value -ErrorAction SilentlyContinue).$Value
# "현재 AC 전원 설정 색인: 0x…" 줄만 집는다 — 첫 hex 는 "가능한 최솟값"(0)이라 09-24 에 0 으로 백업되는 사고가 났다
$idle = ((powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE | Select-String 'AC.*(0x[0-9a-fA-F]{8})\s*$' | Select-Object -First 1).Matches.Groups[1].Value)
Log "armed — $Value = $orig (백업), 시험값 $Data / VIDEOIDLE AC = $idle"
try {
    Set-ItemProperty $key -Name $Value -Value $Data -Type DWord
    Log ("set $Value = " + (Get-ItemProperty $key -Name $Value).$Value)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 60; powercfg /setactive SCHEME_CURRENT
    Restart-Gpu
    Start-Sleep -Seconds 120    # 화면이 다시 꺼질 시간
    $etl = Join-Path $d "g80sh-exp-$Tag.etl"
    & $x -start G80SHExp -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x101:5+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $etl -BufferSize 1024 -MinBuffers 64 -MaxBuffers 512 -MaxFile 4096 -FileMode Sequential 2>&1 | Out-Null
    Log 'capture start'
    Start-Sleep -Seconds ($Min * 60)
    & $x -stop G80SHExp 2>&1 | Out-Null
    Log ("capture stop {0:N0} bytes" -f (Get-Item $etl -ErrorAction SilentlyContinue).Length)
}
finally {
    if ($null -ne $orig) { Set-ItemProperty $key -Name $Value -Value $orig -Type DWord } else { Remove-ItemProperty $key -Name $Value -ErrorAction SilentlyContinue }
    Log ("restored $Value = " + (Get-ItemProperty $key -Name $Value -ErrorAction SilentlyContinue).$Value)
    if ($idle) { powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE ([Convert]::ToInt32($idle, 16)); powercfg /setactive SCHEME_CURRENT }
    Log "VIDEOIDLE AC restored = $([Convert]::ToInt32($idle, 16))"
    Restart-Gpu
    Log 'done — task unregister'
    Unregister-ScheduledTask -TaskName 'G80SH Exp Reg' -Confirm:$false
}
