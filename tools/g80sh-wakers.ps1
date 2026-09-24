# g80sh-wakers.ps1 — 티켓 20. 정밀 캡처(g80sh-deep-capture.ps1)에서 GPU D3→D0 복귀마다 깨운 프로그램을 뽑는다.
#   1) DxgKrnl DdiSetPowerState(154) 로 D0 요청 시각을 찾고
#   2) 그 앞 0.4초 구간만 xperf 로 심볼과 함께 풀어
#   3) tools\g80sh-wakers.py 로 DpiRequestDevicePowerState 를 부른 프로세스를 찾는다.
param([Parameter(Mandatory)][string]$Etl)
$env:_NT_SYMBOL_PATH = 'srv*C:\symbols*https://msdl.microsoft.com/download/symbols'
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$tmp = Join-Path $env:TEMP 'g80sh-wakers'
New-Item -ItemType Directory -Force $tmp | Out-Null
$t0  = (Get-WinEvent -Path $Etl -Oldest -MaxEvents 1).TimeCreated
$d0  = @(Get-WinEvent -Path $Etl -Oldest -FilterXPath '*[System[(EventID=154)]]' -ErrorAction SilentlyContinue |
         Where-Object { $_.ProviderName -like '*DxgKrnl*' -and $_.Properties[2].Value -eq 1 })
"D0 복귀 {0}회" -f $d0.Count
$i = 0
foreach ($e in $d0) {
    $i++
    $rel = [int64](($e.TimeCreated - $t0).TotalMilliseconds * 1000)
    $f = Join-Path $tmp "w$i.txt"
    & $x -i $Etl -o $f -symbols -a dumper -range ($rel - 400000) ($rel + 20000) 2>&1 | Out-Null
    $r = & python 'C:\dev\1_PC_Setup\tools\g80sh-wakers.py' $f
    $who = if ($r) { ($r | ForEach-Object { ($_ -split "`t")[2] + ' ' + ($_ -split "`t")[3] }) -join ' / ' } else { '(프로그램 경로 없음 — 커널/드라이버 자체)' }
    "{0,3}  {1:HH:mm:ss.fff}  {2}" -f $i, $e.TimeCreated, $who
    Remove-Item $f -ErrorAction SilentlyContinue
}
