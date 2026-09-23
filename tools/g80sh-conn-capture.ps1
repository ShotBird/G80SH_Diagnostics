# g80sh-conn-capture.ps1 — 티켓 18. AMD 가 보고하는 연결 변경(DdiQueryConnectionChange)을 폭풍 중에 길게 담는다.
#
# 17 에서 표본 2개로 본 "AMD 전 포트 일괄 보고 → 약 1.4초 → Q1" 을 사이클 수십 개로 확인하려는 것.
# 스택은 필요 없다(판정은 타임스탬프와 페이로드만 쓴다) — 그래서 커널 로거 없이 가볍다.
# 기존 'G80SH ETW Auto'(logman, DxgKrnl 0x100 만)와 별개 세션이다. 그쪽은 건드리지 않는다.
#
# 임시 작업 'G80SH Conn Capture' (SYSTEM) 로 돈다. $Captures 건을 잡으면 작업을 스스로 지운다.
param(
    [int]$Captures = 3,
    [int]$Sec      = 600,
    [int]$CoolMin  = 10
)
$ErrorActionPreference = 'Continue'
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$d   = 'C:\dev\PC\_evidence\conntest'
$log = Join-Path $d 'conn-capture.log'
$dev = 'SAM7B0C'
New-Item -ItemType Directory -Force $d | Out-Null
function Log($m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }
function Count-Recent($sec) {
    @(Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-Kernel-PnP/Device Management'; Id = 1010
        StartTime = (Get-Date).AddSeconds(-$sec)
    } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match $dev }).Count
}

Log "armed (captures=$Captures sec=$Sec cool=${CoolMin}m)"
$done = 0
while ($done -lt $Captures) {
    if ((Count-Recent 90) -ge 2) {
        $done++
        $tag = "{0}-{1}" -f (Get-Date -Format 'MMdd-HHmm'), $done
        $etl = Join-Path $d "g80sh-conn-$tag.etl"
        & $x -start G80SHConn -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x101:5+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $etl -BufferSize 1024 -MinBuffers 64 -MaxBuffers 256 2>&1 | Out-Null
        Log "#$done start $tag"
        Start-Sleep -Seconds $Sec
        & $x -stop G80SHConn 2>&1 | Out-Null
        Log ("#$done stop {0:N0} bytes" -f (Get-Item $etl -ErrorAction SilentlyContinue).Length)
        if ($done -lt $Captures) { Start-Sleep -Seconds ($CoolMin * 60) }
    } else { Start-Sleep -Seconds 15 }
}
Log 'done — task unregister'
Unregister-ScheduledTask -TaskName 'G80SH Conn Capture' -Confirm:$false
