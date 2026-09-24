# g80sh-power-compare.ps1 — 티켓 20. 완화책(GPU D3 차단) 켠 때와 끈 때의 전력을 짧게 비교한다.
#
# 화면이 실제로 꺼지고 G80SH 가 활성 구성에 있을 때만 의미가 있다(원격 접속 중엔 REMOTE 레이아웃이라 G80SH 비활성 — 09-24 08:07 무효).
# → 폭풍이 실제로 돌고 있을 때(최근 120초에 SAM7B0C 1010 2건 이상)를 시작 조건으로 쓴다. 화면 꺼짐 시간은 건드리지 않는다.
# 구간: B(평소, D3 순환·폭풍) $B 분 → A(ffmpeg 로 D3 차단) $A 분 → B2(평소) $B2 분. 1초마다 LibreHardwareMonitor 에서
#   RX 9070 XT GPU Package W, CPU Package W 를 읽는다. 구간별 평균·사이클 수를 낸다. 끝나면 화면 꺼짐 시간을 되돌린다.
# 한계: LHM 조회 자체가 GPU 를 깨우는 쪽 중 하나다(세 구간 공통). 벽 콘센트 전력이 아니라 센서 값이다.
param([int]$B = 5, [int]$A = 5, [int]$B2 = 3)
$d   = 'C:\dev\1_PC_Setup\_evidence\power-compare'
New-Item -ItemType Directory -Force $d | Out-Null
$csv = Join-Path $d ("power-{0}.csv" -f (Get-Date -Format 'MMdd-HHmm'))
$log = Join-Path $d 'power.log'
$ff  = 'C:\Program Files\TRCCCAP\ffmpeg.exe'
function Log($m) { $l = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m; Add-Content -LiteralPath $log -Value $l -Encoding UTF8; Write-Host $l }
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Idle2 {
  [StructLayout(LayoutKind.Sequential)] struct LII { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LII p);
  public static uint Ms() { var l = new LII(); l.cbSize = (uint)Marshal.SizeOf(l); GetLastInputInfo(ref l); return (uint)Environment.TickCount - l.dwTime; }
}
'@
function Sensors {
    try {
        $j = Invoke-RestMethod -Uri 'http://127.0.0.1:8085/data.json' -TimeoutSec 2
        $g = $null; $c = $null
        $stack = New-Object System.Collections.Stack; $stack.Push($j)
        while ($stack.Count) { $n = $stack.Pop()
            if ($n.SensorId -eq '/gpu-amd/5/power/3') { $g = [double](($n.Value -replace '[^\d\.]', '')) }
            if ($n.SensorId -eq '/amdcpu/0/power/0') { $c = [double](($n.Value -replace '[^\d\.]', '')) }
            foreach ($ch in $n.Children) { $stack.Push($ch) } }
        return @($g, $c)
    } catch { return @($null, $null) }
}
function Phase($name, $min) {
    $t0 = Get-Date; $n = 0; $gs = 0; $cs = 0; $gz = 0
    while (((Get-Date) - $t0).TotalMinutes -lt $min) {
        $s = Sensors
        if ($s[0] -ne $null) { $n++; $gs += $s[0]; $cs += $s[1]; if ($s[0] -lt 1) { $gz++ } }
        Add-Content -LiteralPath $csv -Value ("{0},{1},{2},{3},{4:N0}" -f (Get-Date -Format 'HH:mm:ss'), $name, $s[0], $s[1], ([Idle2]::Ms() / 1000))
        Start-Sleep -Seconds 1
    }
    $cyc = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Device Management'; Id = 1010; StartTime = $t0 } -ErrorAction SilentlyContinue | Where-Object Message -match 'SAM7B0C').Count
    $idleOk = ([Idle2]::Ms() / 1000) -ge ($min * 60)
    Log ("{0}: {1:N1}분  GPU 평균 {2:N2} W  CPU 평균 {3:N2} W  표본 {4}  (GPU 1W 미만 {5})  사이클 {6}  입력없음유지 {7}" -f $name, $min, ($gs / [Math]::Max($n, 1)), ($cs / [Math]::Max($n, 1)), $n, $gz, $cyc, $idleOk)
}

$orig = ((powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE | Select-String 'AC.*(0x[0-9a-fA-F]{8})\s*$' | Select-Object -First 1).Matches.Groups[1].Value)
$origSec = [Convert]::ToInt32($orig, 16)
Add-Content -LiteralPath $csv -Value 'time,phase,gpu_w,cpu_w,idle_s'
Log "armed — 폭풍이 도는 상태(최근 120초 SAM7B0C 1010 ≥2)를 기다린다 (VIDEOIDLE AC $origSec 유지)"
$p = $null
function Storming { @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Device Management'; Id = 1010; StartTime = (Get-Date).AddSeconds(-120) } -ErrorAction SilentlyContinue | Where-Object Message -match 'SAM7B0C').Count -ge 2 }
try {
    while (-not (Storming)) { Start-Sleep -Seconds 15 }
    Log 'storm 확인 — 측정 시작'
    Phase 'B-normal' $B
    $p = Start-Process $ff -ArgumentList '-hide_banner -loglevel error -re -f lavfi -i testsrc=size=320x240:rate=2 -c:v h264_amf -f null -' -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 20
    Phase 'A-keepalive' $A
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $p = $null
    Start-Sleep -Seconds 20
    Phase 'B2-normal' $B2
}
finally {
    if ($p) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Log "done — csv $csv"
}
