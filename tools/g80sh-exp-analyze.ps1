# g80sh-exp-analyze.ps1 — 티켓 20. 시험 구간 ETL 마다 GPU D3 진입·전 포트 재감지·Q1 과 1010 사이클을 센다.
param([string]$Dir = 'C:\dev\PC\_evidence\exp-trcc')
$xp = "*[System[(EventID=154 or EventID=1099)]]"
foreach ($f in Get-ChildItem $Dir -Filter 'g80sh-exp-*.etl' | Sort-Object Name) {
    $ev = @(Get-WinEvent -Path $f.FullName -Oldest -FilterXPath $xp -ErrorAction SilentlyContinue | Where-Object ProviderName -like '*DxgKrnl*')
    if (-not $ev) { "{0}: 이벤트 없음" -f $f.Name; continue }
    $all = @(Get-WinEvent -Path $f.FullName -Oldest -MaxEvents 1 -ErrorAction SilentlyContinue)
    $t0 = $all[0].TimeCreated; $t1 = $ev[-1].TimeCreated
    $d3 = @($ev | Where-Object { $_.Id -eq 154 -and $_.Properties[2].Value -eq 4 }).Count
    # 1099 를 5ms 배치로 묶어 일괄(≥8)·Q1(260: 8 → 10) 을 센다
    $batches = @(); $cur = $null
    foreach ($e in ($ev | Where-Object { $_.Id -eq 1099 -and $_.Properties[1].Value -ne 0 })) {
        if ($cur -and ($e.TimeCreated - $cur.t1).TotalMilliseconds -le 5) { $cur.items += ,@($e.Properties[2].Value, $e.Properties[3].Value); $cur.t1 = $e.TimeCreated }
        else { $cur = [pscustomobject]@{ t = $e.TimeCreated; t1 = $e.TimeCreated; items = @(,@($e.Properties[2].Value, $e.Properties[3].Value)) }; $batches += $cur }
    }
    $sweeps = @($batches | Where-Object { $_.items.Count -ge 8 }).Count
    $q1 = @($batches | Where-Object { $g = @($_.items | Where-Object { $_[0] -eq 260 } | ForEach-Object { $_[1] }); ($g -join ',') -eq '8,10' }).Count
    $cyc = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Device Management'; Id = 1010; StartTime = $t0; EndTime = $t1 } -ErrorAction SilentlyContinue | Where-Object Message -match 'SAM7B0C').Count
    $scr = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 566; StartTime = $t0; EndTime = $t1 } -ErrorAction SilentlyContinue).Count
    $min = ($t1 - $t0).TotalMinutes
    "{0}  {1:HH:mm:ss}~{2:HH:mm:ss} ({3:N1}분)  GPU D3 진입 {4}  전포트 재감지 {5}  Q1 {6}  SAM7B0C 1010 {7}  (시간당 사이클 {8:N1})  화면 전환(566) {9}" -f `
        $f.Name, $t0, $t1, $min, $d3, $sweeps, $q1, $cyc, ($cyc / $min * 60), $scr
}
