# g80sh-emul-test.ps1 — AMD EDID 에뮬레이션 왕복 실험 (06)
#
# 폭풍이 확실히 도는 것을 확인한 뒤에만 켠다. 폭풍이 멎은 뒤에 켜면 무조건
# "멎었다"가 나온다(거짓 양성). 그래서 phase 1 에서 양성 대조군을 먼저 확보한다.
#
#   phase 1  폭풍 재개 대기 (120초에 2건 이상)   최대 8분
#   phase 2  에뮬레이션 ON (mode 2 ON_DISCONNECTED)
#   phase 3  5분 관측 — 멎는가
#   phase 4  에뮬레이션 OFF
#   phase 5  5분 관측 — 다시 나는가
#
# 복구는 3중으로 걸려 있다: boot(onstart) / logon / timer(18:22)
param(
    [int]$WaitMax = 8,
    [int]$ObsMin  = 5,
    [int]$Mode    = 2
)
$ErrorActionPreference = 'Continue'
$py  = 'C:\Users\hans1\AppData\Local\Programs\Python\Python313\python.exe'
$scr = 'C:\dev\1_PC_Setup\tools\g80sh_edid_emul.py'
$log = 'C:\dev\1_PC_Setup\_evidence\emul-test.log'

function Log($m) {
    $line = "{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}
function Cnt($sec) {
    @(Get-WinEvent -FilterHashtable @{
        LogName='Microsoft-Windows-Kernel-PnP/Device Management'; Id=1010
        StartTime=(Get-Date).AddSeconds(-$sec)} -ErrorAction SilentlyContinue |
      Where-Object { $_.Message -match 'SAM7B0C|Default_Monitor' }).Count
}
function Events($from) {
    @(Get-WinEvent -FilterHashtable @{
        LogName='Microsoft-Windows-Kernel-PnP/Device Management'; Id=1010; StartTime=$from
      } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'DISPLAY\\' })
}

"=== 06 EDID 에뮬레이션 왕복 실험  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content $log -Encoding UTF8
Log "복구: boot(onstart) / logon / timer(18:22) 3중"

# ---- phase 1 : 양성 대조군 확보 ----
Log "[1] 폭풍 재개 대기 (120초에 2건 이상, 최대 ${WaitMax}분)"
$deadline = (Get-Date).AddMinutes($WaitMax)
$armed = $false
while ((Get-Date) -lt $deadline) {
    $n = Cnt 120
    if ($n -ge 2) { $armed = $true; Log "[1] 폭풍 확인 (120초에 ${n}건) — 양성 대조군 확보"; break }
    Start-Sleep -Seconds 15
}
if (-not $armed) {
    Log "[1] 시간 초과. 폭풍이 돌지 않아 실험을 하지 않는다. 에뮬레이션은 건드리지 않았다."
    Log "=== 종료 (실험 안 함) ==="
    exit 0
}

# ---- phase 2 : ON ----
$tOn = Get-Date
Log "[2] 에뮬레이션 ON (mode=$Mode)"
& $py $scr on $Mode 2>&1 | ForEach-Object { Log "    $_" }

# ---- phase 3 : 관측 ----
Log "[3] ${ObsMin}분 관측 — 멎는가"
for ($i=0; $i -lt ($ObsMin*3); $i++) {
    Start-Sleep -Seconds 20
    $e = Events $tOn
    Log ("    +{0,4}s  1010={1}" -f [int]((Get-Date)-$tOn).TotalSeconds, $e.Count)
}
$onEvents = Events $tOn
Log ("[3] 결과: ON 구간 ${ObsMin}분 동안 " + $onEvents.Count + "건")
$onEvents | Sort-Object TimeCreated | ForEach-Object { Log ("      {0}  {1}" -f $_.TimeCreated.ToString('HH:mm:ss.fff'), $(if($_.Message -match 'DISPLAY\\([A-Za-z0-9_]+)\\'){$matches[1]})) }

# ---- phase 4 : OFF ----
$tOff = Get-Date
Log "[4] 에뮬레이션 OFF"
& $py $scr off 2>&1 | ForEach-Object { Log "    $_" }

# ---- phase 5 : 관측 ----
Log "[5] ${ObsMin}분 관측 — 다시 나는가"
for ($i=0; $i -lt ($ObsMin*3); $i++) {
    Start-Sleep -Seconds 20
    $e = Events $tOff
    Log ("    +{0,4}s  1010={1}" -f [int]((Get-Date)-$tOff).TotalSeconds, $e.Count)
}
$offEvents = Events $tOff
Log ("[5] 결과: OFF 구간 ${ObsMin}분 동안 " + $offEvents.Count + "건")
$offEvents | Sort-Object TimeCreated | ForEach-Object { Log ("      {0}  {1}" -f $_.TimeCreated.ToString('HH:mm:ss.fff'), $(if($_.Message -match 'DISPLAY\\([A-Za-z0-9_]+)\\'){$matches[1]})) }

Log ""
Log ("판정: ON " + $onEvents.Count + "건  vs  OFF " + $offEvents.Count + "건")
& $py $scr status 2>&1 | ForEach-Object { Log "    $_" }
Log "=== 종료 ==="
