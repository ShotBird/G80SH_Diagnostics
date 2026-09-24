# g80sh-exp-disable.ps1 — 티켓 21 B안/B+안(-Both: Default_Monitor UID260 도 함께). 화면이 꺼진 동안 G80SH 모니터 장치를 '사용 안 함'(Disable-PnpDevice)으로 두면 폭풍이 멎는가.
# (A안 g80sh-exp-detach.ps1 — 화면 구성 분리 — 는 기각. 이 파일은 그 구조를 따른다)
#
# 근거: 원격 접속 중(09-24 06:46~09:01, REMOTE 레이아웃 — G80SH 비활성) 폭풍 0건.
#       단 원격 중엔 GPU 가 원격 화면을 만드느라 계속 일했을 수 있다(D3 가 없어서 멎은 것일 수도) → 원격 없이 가른다.
# 순서: 감시자(RemoteDisplaySwitch) 일시 정지 → VIDEOIDLE 60 임시 → 폭풍 확인 → 캡처 시작
#       → 기준 $Base 분(평소 구성) → G50F 단독 구성 + 전원 설정 재적용(꺼짐 타이머 재무장) → $Min 분
#       → 입력 복귀 확인: 가짜 입력(감시자와 같은 SendInput)으로 화면을 깨우고 G80SH 가 붙을 수 있는 상태로 돌아오는지, 평소 구성 복귀까지 몇 초인지
#       → 평소 구성 복구 → 감시자 재시작 → VIDEOIDLE 복구.
# 사용자 세션·관리자 권한 임시 작업 'G80SH Exp Disable'. 사슬 검증용 시험이다(상시규칙 1).
param([int]$Base = 3, [int]$Min = 3, [switch]$Both)
. 'C:\dev\1_PC_Setup\RemoteDisplaySwitch\SwitchLib.ps1'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class ExpInput {
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint f);
    public static uint Wake() {
        var a = new INPUT[2];
        a[0].type = 0; a[0].u.mi.dx = 1;  a[0].u.mi.dwFlags = 1;
        a[1].type = 0; a[1].u.mi.dx = -1; a[1].u.mi.dwFlags = 1;
        SetThreadExecutionState(0x00000002);
        return SendInput(2, a, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$d   = 'C:\dev\1_PC_Setup\_evidence\exp-disable'
$log = Join-Path $d 'exp.log'
New-Item -ItemType Directory -Force $d | Out-Null
function Log($m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }
function Cyc($t0) { @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Device Management'; Id = 1010; StartTime = $t0 } -ErrorAction SilentlyContinue | Where-Object Message -match 'SAM7B0C').Count }
$dev = 'DISPLAY\SAM7B0C\7&16B8DDB4&0&UID260'
$dev2 = 'DISPLAY\DEFAULT_MONITOR\7&16B8DDB4&0&UID260'
function All($t0) { @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Device Management'; Id = 1010; StartTime = $t0 } -ErrorAction SilentlyContinue | Where-Object { $_.Properties[0].Value -like 'DISPLAY\*' }).Count }
function Storming { (Cyc (Get-Date).AddSeconds(-120)) -ge 2 }
function Watchers { @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -match 'RemoteDisplaySwitch\.ps1') }

$idle = [Convert]::ToInt32(((powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE | Select-String 'AC.*(0x[0-9a-fA-F]{8})\s*$' | Select-Object -First 1).Matches.Groups[1].Value), 16)
Log "armed — VIDEOIDLE AC $idle, layout: $((Get-Layout).Active -join ',')"
Stop-ScheduledTask -TaskName 'Remote Display Switch' -ErrorAction SilentlyContinue
Watchers | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Log ("watcher stopped (남은 {0})" -f (Watchers).Count)
powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 60; powercfg /setactive SCHEME_CURRENT
$etl = Join-Path $d 'g80sh-exp-disable.etl'
try {
    $w0 = Get-Date
    while (-not (Storming)) { Start-Sleep -Seconds 15; if (((Get-Date) - $w0).TotalMinutes -gt 30) { Log '30분 기다려도 폭풍 없음 — 중단'; return } }
    & $x -start G80SHExp -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x101:5+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $etl -BufferSize 1024 -MinBuffers 64 -MaxBuffers 512 -MaxFile 4096 -FileMode Sequential 2>&1 | Out-Null
    $t0 = Get-Date; Log 'storm 확인 — 캡처 시작, 기준 구간(평소 구성)'
    Start-Sleep -Seconds ($Base * 60)
    Log ("기준 {0}분: 사이클 {1}" -f $Base, (Cyc $t0))
    Disable-PnpDevice -InstanceId $dev -Confirm:$false -ErrorAction SilentlyContinue
    if ($Both) {
        $e2 = $null; try { Disable-PnpDevice -InstanceId $dev2 -Confirm:$false -ErrorAction Stop } catch { $e2 = $_.Exception.Message }
        $cf = (Get-PnpDeviceProperty -InstanceId $dev2 -KeyName DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue).Data
        Log ("Default_Monitor UID260 사용 안 함 시도: " + $(if ($e2) { "오류 $e2" } else { 'OK' }) + " / present=$((Get-PnpDevice -InstanceId $dev2 -ErrorAction SilentlyContinue).Present) problem=$cf")
    }
    powercfg /setactive SCHEME_CURRENT
    Start-Sleep -Seconds 5
    $t1 = Get-Date; Log ("G80SH 사용 안 함: status=$((Get-PnpDevice -InstanceId $dev -ErrorAction SilentlyContinue).Status) → layout: $((Get-Layout).Active -join ',') / 전원 설정 재적용")
    for ($i = 1; $i -le $Min; $i++) {
        Start-Sleep -Seconds 60
        Log ("  +{0}분 사이클 누적 {1}  1010(전체 DISPLAY) {2}  status {3}  layout {4}" -f $i, (Cyc $t1), (All $t1), (Get-PnpDevice -InstanceId $dev -ErrorAction SilentlyContinue).Status, ((Get-Layout).Active -join ','))
    }
    Log ("사용 안 함 {0}분: 사이클 {1} / DISPLAY 1010 전체 {2}" -f $Min, (Cyc $t1), (All $t1))
    # 입력 복귀 확인
    $tw = Get-Date
    Log ("입력 주입: {0}" -f [ExpInput]::Wake())
    Enable-PnpDevice -InstanceId $dev -Confirm:$false -ErrorAction SilentlyContinue
    if ($Both) { Enable-PnpDevice -InstanceId $dev2 -Confirm:$false -ErrorAction SilentlyContinue }
    Log ("장치 다시 켬: status=$((Get-PnpDevice -InstanceId $dev -ErrorAction SilentlyContinue).Status)")
    $avail = $null
    for ($k = 0; $k -lt 30; $k++) {
        Start-Sleep -Seconds 1
        if ((Get-Available) -contains $G80) { $avail = ((Get-Date) - $tw).TotalSeconds; break }
    }
    Log ("G80SH 붙일 수 있게 됨: {0}" -f $(if ($avail -ne $null) { '{0:N1}초' -f $avail } else { '30초 안에 안 됨 (available: ' + ((Get-Available) -join ',') + ')' }))
    $h0 = Get-Date
    $h = Switch-ToHome
    Log ("입력 후 평소 구성 복귀 ok={0} active={1} primary={2} ({3:N1}초, 입력부터 {4:N1}초)" -f $h.Ok, $h.Active, $h.Primary, ((Get-Date) - $h0).TotalSeconds, ((Get-Date) - $tw).TotalSeconds)
}
finally {
    & $x -stop G80SHExp 2>&1 | Out-Null
    Enable-PnpDevice -InstanceId $dev -Confirm:$false -ErrorAction SilentlyContinue
    if ($Both) { Enable-PnpDevice -InstanceId $dev2 -Confirm:$false -ErrorAction SilentlyContinue }
    Log ("안전장치 — 장치 켬 확인: status=$((Get-PnpDevice -InstanceId $dev -ErrorAction SilentlyContinue).Status)")
    if (-not (Is-HomeLayout (Get-Layout))) { $h = Switch-ToHome; Log ("HOME 복구 ok={0} active={1}" -f $h.Ok, $h.Active) } else { Log 'HOME 상태 확인' }
    powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE $idle; powercfg /setactive SCHEME_CURRENT
    Start-ScheduledTask -TaskName 'Remote Display Switch' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    Log ("VIDEOIDLE AC 복구 $idle / watcher 재시작 {0}" -f (Watchers).Count)
    Log 'done — task unregister'
    Unregister-ScheduledTask -TaskName 'G80SH Exp Disable' -Confirm:$false -ErrorAction SilentlyContinue
}
