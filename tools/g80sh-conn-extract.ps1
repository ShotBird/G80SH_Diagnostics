# g80sh-conn-extract.ps1 — 티켓 18. 연결 변경 캡처에서 판정에 필요한 이벤트만 CSV 로 뽑는다.
#   DxgKrnl 1099  DdiQueryConnectionChange Stop  (a = TargetId, b = ConnectionStatus, c = ConnectionChangeId)
#   Kernel-PnP 220 (GPU 만) / 1010
# 출력: _evidence\conntest\g80sh-conn-events.csv  -> tools\g80sh-conn.py
param([string[]]$Etl = @(Get-ChildItem 'C:\dev\1_PC_Setup\_evidence\conntest\g80sh-conn-*.etl', 'C:\dev\1_PC_Setup\_evidence\stacktest\g80sh-xperf-*-dxgbase.etl' -ErrorAction SilentlyContinue | ForEach-Object FullName),
      [string]$Out = 'C:\dev\1_PC_Setup\_evidence\conntest\g80sh-conn-events.csv')
$out = $Out
$xp  = "*[System[(EventID=1099 or EventID=220 or EventID=1010)]]"
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('file,time,id,a,b,c')
foreach ($f in $Etl) {
    $n = Split-Path $f -Leaf
    $ev = Get-WinEvent -Path $f -Oldest -FilterXPath $xp -ErrorAction SilentlyContinue
    foreach ($e in $ev) {
        $p = $e.Properties
        if ($e.Id -eq 1099) { $a = $p[2].Value; $b = $p[3].Value; $c = $p[1].Value }
        elseif ($e.Id -eq 220) { if ("$($p[1].Value)" -notlike 'PCI\VEN_1002&DEV_7550*') { continue }; $a = 'GPU'; $b = ''; $c = '' }
        else { $a = $p[0].Value; $b = ''; $c = '' }
        $rows.Add(('{0},{1},{2},"{3}",{4},{5}' -f $n, $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss.ffffff'), $e.Id, $a, $b, $c))
    }
    Write-Host "$n $($ev.Count)"
}
[IO.File]::WriteAllLines($out, $rows)
