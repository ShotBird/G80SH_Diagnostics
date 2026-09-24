# g80sh-etw-capture.ps1 - G80SH 1010 반복 구간의 ETW 캡처
#
# 목적: "약 48초마다 무엇이 재열거를 촉발하는가"의 선후 관계를 잡는다.
#   모니터가 먼저 링크를 놓음  -> DxgKrnl StatusChangeNotify 가 앞선다
#   OS/드라이버가 먼저 조회함  -> Kernel-PnP 220 (Begin querying bus relations) 이 앞선다
#
# provider 는 2026-09-18 실측(60초 525,469건 분석)으로 선별했다. 재선별하지 말 것.
#   Dxgkrnl_StatusChangeNotify (0x100)  0/초  - 상태 변경 시에만
#   Kernel-PnP  verbose                273/초 - 220/222/808/1010
#   제외: Kernel-Power(8,020/초), DxgKrnl Base(2,381/초), DxgKrnl_Power(465/초)
#
# 관리자 권한 필요 (logman -ets).
param(
    [int]$Minutes = 12,
    [string]$Tag  = (Get-Date -Format 'MMdd-HHmm')
)

$ErrorActionPreference = 'Continue'
$out     = 'C:\dev\1_PC_Setup\_evidence'
$session = 'G80SH'
$etl     = Join-Path $out "g80sh-dxg-$Tag.etl"
$csv     = Join-Path $out "g80sh-dxg-$Tag.csv"
$agg     = Join-Path $out "g80sh-dxg-agg-$Tag.txt"
$log     = Join-Path $out 'auto.log'

function Log($m) {
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Output $line
}

New-Item -ItemType Directory -Force -Path $out | Out-Null

# --- 남아있는 세션 정리 -------------------------------------------------------
logman stop $session -ets 2>&1 | Out-Null

# --- 시작 ---------------------------------------------------------------------
Log "capture start tag=$Tag minutes=$Minutes -> $etl"

$create = logman create trace $session -ow -o $etl `
    -p '{802EC45A-1E99-4B83-9920-87C98277BA9D}' 0x100 0xff `
    -nb 32 64 -bs 64 -mode Circular -f bincirc -max 512 -ets 2>&1
if ($LASTEXITCODE -ne 0) { Log "logman create FAILED: $create"; exit 1 }

$upd = logman update trace $session `
    -p '{9C205A39-1250-487D-ABD7-E831C6290539}' 0xffffffffffffffff 0xff -ets 2>&1
if ($LASTEXITCODE -ne 0) { Log "logman update(Kernel-PnP) FAILED: $upd" }

# --- 캡처 중 1010 발생 시각을 별도로 기록 (ETL 밖 기준선) ---------------------
$t0 = Get-Date
Start-Sleep -Seconds ($Minutes * 60)
$t1 = Get-Date

logman stop $session -ets 2>&1 | Out-Null
Log "capture stop  ($([int]($t1-$t0).TotalSeconds)s)"

if (-not (Test-Path $etl)) { Log "NO ETL PRODUCED"; exit 1 }
Log ("etl size {0:N0} bytes" -f (Get-Item $etl).Length)

# --- 디코드 -------------------------------------------------------------------
$ev = Get-WinEvent -Path $etl -Oldest -ErrorAction SilentlyContinue
if (-not $ev) { Log "decode produced 0 events"; exit 1 }
Log ("decoded {0:N0} events" -f $ev.Count)

# 관심 이벤트만 남긴다.
#   Kernel-PnP : 220 bus relations 조회 시작 / 222 완료 / 808 / 1010 제거
#   DxgKrnl    : StatusChangeNotify 전량
$pnpIds = 220, 221, 222, 225, 400, 410, 420, 430, 441, 442, 808, 1010
$keep = $ev | Where-Object {
    ($_.ProviderName -like '*Kernel-PnP*' -and $pnpIds -contains $_.Id) -or
    ($_.ProviderName -like '*DxgKrnl*')
}
Log ("kept {0:N0} events" -f $keep.Count)

$keep | ForEach-Object {
    [pscustomobject]@{
        Time     = $_.TimeCreated.ToString('HH:mm:ss.fffffff')
        Provider = ($_.ProviderName -replace '^Microsoft-Windows-', '')
        Id       = $_.Id
        Opcode   = $_.OpcodeDisplayName
        Task     = $_.TaskDisplayName
        Message  = (($_.Message -replace "`r?`n", ' | ') -replace '\s+', ' ')
    }
} | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Log "csv -> $csv"

# --- 요약: 1010 각 건의 -6초 ~ +2초 구간에서 무엇이 먼저 왔는가 ---------------
$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

W "G80SH ETW capture $Tag   $($t0.ToString('yyyy-MM-dd HH:mm:ss')) ~ $($t1.ToString('HH:mm:ss'))"
W ""
W "== provider/id 분포 =="
$keep | Group-Object { "{0} {1}" -f ($_.ProviderName -replace '^Microsoft-Windows-',''), $_.Id } |
    Sort-Object Count -Descending | ForEach-Object { W ("{0,-48} {1,6}" -f $_.Name, $_.Count) }

$marks = $keep | Where-Object { $_.Id -eq 1010 -and $_.Message -match 'SAM7B0C' }
W ""
W "== SAM7B0C 1010: $($marks.Count) 건 =="

foreach ($m in $marks) {
    $a = $m.TimeCreated.AddSeconds(-6)
    $b = $m.TimeCreated.AddSeconds(2)
    $win = $keep | Where-Object { $_.TimeCreated -ge $a -and $_.TimeCreated -le $b }
    W ""
    W ("---- 1010 @ {0} ----" -f $m.TimeCreated.ToString('HH:mm:ss.fff'))
    foreach ($e in $win) {
        $d = ($e.TimeCreated - $m.TimeCreated).TotalMilliseconds
        W ("{0,9:+0;-0;0}ms  {1,-22} {2,5}  {3}" -f $d,
            ($e.ProviderName -replace '^Microsoft-Windows-',''), $e.Id,
            (($e.Message -replace "`r?`n",' ' -replace '\s+',' ')))
    }
}

Set-Content -LiteralPath $agg -Value $sb.ToString() -Encoding UTF8
Log "agg -> $agg"
Log "capture done tag=$Tag"
