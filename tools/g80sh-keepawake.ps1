# g80sh-keepawake.ps1 — 완화책 시제품 (티켓 20). **배포하지 않았다 — 사용자 결정 대기.**
#
# 20-8 에서 확정: 화면이 꺼진 동안 GPU 가 D3 ↔ D0 를 오갈 때마다 AMD 가 재감지하고, 그때 G80SH 가 끊긴다.
# GPU 를 D0 에 붙잡으면 30분 0건, 풀면 27초 만에 재발.
# 이 스크립트는 "화면이 꺼져 있을 동안에만" GPU 에 아주 가벼운 하드웨어 인코딩(320x240 2fps)을 걸어 D3 진입을 막는다.
#
# ⚠ 우회책이다(맵 상시규칙 1). 증상을 가릴 뿐 모니터 결함은 그대로다. 삼성 제출 전에는 켜지 말 것
#   (켜 두면 증거가 안 쌓인다). 대가: 화면 꺼진 동안 GPU 가 저전력 절전에 못 들어가 대기 전력이 조금 는다.
#
# 화면 상태 판정: 마지막 입력 후 경과 ≥ 화면 끄기 시간(VIDEOIDLE AC) 이면 꺼진 것으로 본다.
#   원격 접속·영상 재생 등으로 화면이 켜져 있어도 입력이 없으면 켜질 수 있다 — 그래도 해는 없다(GPU 가 조금 더 깨어 있을 뿐).
# 사용자 세션에서 돌아야 한다(GetLastInputInfo). 작업 스케줄러 등록 예시는 파일 끝 주석.
param([int]$PollSec = 5)
$ff = 'C:\Program Files\TRCCCAP\ffmpeg.exe'
$args_ = '-hide_banner -loglevel error -re -f lavfi -i testsrc=size=320x240:rate=2 -c:v h264_amf -f null -'
$log = 'C:\ProgramData\G80SH-keepawake.log'
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Idle {
  [StructLayout(LayoutKind.Sequential)] struct LII { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LII p);
  public static uint Ms() { var l = new LII(); l.cbSize = (uint)Marshal.SizeOf(l); GetLastInputInfo(ref l); return (uint)Environment.TickCount - l.dwTime; }
}
'@
function Log($m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }
function TimeoutSec {
    $m = powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE | Select-String 'AC.*(0x[0-9a-fA-F]{8})\s*$' | Select-Object -First 1
    if ($m) { [Convert]::ToInt32($m.Matches.Groups[1].Value, 16) } else { 900 }
}
$p = $null
Log 'keepawake start'
while ($true) {
    $to = TimeoutSec
    $off = ($to -gt 0) -and ((([Idle]::Ms()) / 1000) -ge $to)
    if ($off -and (-not $p -or $p.HasExited)) {
        $p = Start-Process $ff -ArgumentList $args_ -WindowStyle Hidden -PassThru
        Log "display off (timeout ${to}s) → GPU keepalive on (pid $($p.Id))"
    } elseif (-not $off -and $p -and -not $p.HasExited) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Log 'input → GPU keepalive off'
        $p = $null
    }
    Start-Sleep -Seconds $PollSec
}
# 등록 예시 (사용자가 결정한 뒤에만):
#   $a = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\dev\PC\tools\g80sh-keepawake.ps1'
#   Register-ScheduledTask 'G80SH Keepawake' -Action $a -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME)
