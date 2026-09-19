# g80sh-etw-decode.ps1 — 캡처한 .etl 을 사람이 읽을 수 있게 푼다.
#
# 두 가지를 본다:
#   (1) 화면이 꺼지는 순간(DPMS off / DP 링크 다운)에 무엇이 먼저 오는가
#   (2) 그 뒤 48초 주기 각 사이클에서 1010 직전에 무엇이 먼저 오는가
#       모니터 선행 -> DxgKrnl StatusChangeNotify
#       OS/드라이버 선행 -> Kernel-PnP 220 (Begin querying bus relations)
param(
    [Parameter(Mandatory)][string]$Etl,
    [string]$Tag = (Get-Date -Format 'MMdd-HHmm')
)

$ErrorActionPreference = 'Continue'
$out = 'C:\dev\PC\_evidence'
$csv = Join-Path $out "g80sh-dxg-$Tag.csv"
$agg = Join-Path $out "g80sh-dxg-agg-$Tag.txt"
$log = Join-Path $out 'auto.log'
function Log($m) {
    Add-Content -LiteralPath $log -Value ("{0} [decode] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8
}

if (-not (Test-Path $Etl)) { Log "no etl: $Etl"; exit 1 }

$ev = Get-WinEvent -Path $Etl -Oldest -ErrorAction SilentlyContinue
if (-not $ev) { Log "decode produced 0 events"; exit 1 }
Log ("decoded {0:N0} events from {1}" -f $ev.Count, (Split-Path $Etl -Leaf))

$pnpIds = 220, 221, 222, 225, 400, 410, 420, 430, 441, 442, 808, 1010
$keep = $ev | Where-Object {
    ($_.ProviderName -like '*Kernel-PnP*' -and $pnpIds -contains $_.Id) -or
    ($_.ProviderName -like '*DxgKrnl*')
}
Log ("kept {0:N0}" -f $keep.Count)

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

$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

W "G80SH ETW $Tag   $(Split-Path $Etl -Leaf)"
W "범위: $($keep[0].TimeCreated.ToString('HH:mm:ss.fff')) ~ $($keep[-1].TimeCreated.ToString('HH:mm:ss.fff'))"
W ""
W "== provider/id 분포 =="
$keep | Group-Object { "{0} {1}" -f ($_.ProviderName -replace '^Microsoft-Windows-',''), $_.Id } |
    Sort-Object Count -Descending | ForEach-Object { W ("{0,-48} {1,8}" -f $_.Name, $_.Count) }

$marks = $keep | Where-Object { $_.Id -eq 1010 -and $_.Message -match 'SAM7B0C' }
W ""
W "== SAM7B0C 1010: $($marks.Count) 건 =="
W ""
W "-- 첫 3건은 화면 꺼짐 전환 구간을 포함해 넓게(-60초), 나머지는 -6초 --"

$i = 0
foreach ($m in $marks) {
    $i++
    $back = if ($i -le 3) { 60 } else { 6 }
    $a = $m.TimeCreated.AddSeconds(-$back)
    $b = $m.TimeCreated.AddSeconds(2)
    $win = $keep | Where-Object { $_.TimeCreated -ge $a -and $_.TimeCreated -le $b }
    W ""
    W ("---- #{0}  1010 @ {1}   (-{2}s 구간, {3}건) ----" -f $i, $m.TimeCreated.ToString('HH:mm:ss.fff'), $back, $win.Count)
    foreach ($e in $win) {
        $d = ($e.TimeCreated - $m.TimeCreated).TotalMilliseconds
        W ("{0,10:+0;-0;0}ms  {1,-22} {2,5}  {3}" -f $d,
            ($e.ProviderName -replace '^Microsoft-Windows-',''), $e.Id,
            (($e.Message -replace "`r?`n",' ' -replace '\s+',' ')))
    }
    if ($i -ge 8) { W ""; W "... (나머지 $($marks.Count - $i) 건은 csv 참조)"; break }
}

Set-Content -LiteralPath $agg -Value $sb.ToString() -Encoding UTF8
Log "agg -> $agg / csv -> $csv"
