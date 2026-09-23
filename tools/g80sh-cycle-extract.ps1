# g80sh-cycle-extract.ps1 — 확보한 ETL 전부에서 폭풍 사이클 분석에 필요한 이벤트만 뽑는다.
#
# g80sh-etw-decode.ps1 은 Message 문자열만 남겨 DxgKrnl 10011 의 Type 필드와
# 807(device add)의 장치 ID 를 잃는다. 여기서는 Properties 를 직접 푼다.
#   220/222  GPU·자식의 버스 관계 조회 (a = 장치)
#   1010     버스에서 누락된 장치 제거  (a = 장치)
#   807      장치 추가                  (a = 드라이버, b = 장치)
#   810/811  재열거 큐잉/시작 (= IoInvalidateDeviceRelations 의 흔적)
#   10011    DxgKrnl StatusChangeNotify (a = Type, b = Source)
# 출력: _evidence\g80sh-cycle-events.csv  -> tools\g80sh-cycle.py 로 분석
$out = 'C:\dev\PC\_evidence\g80sh-cycle-events.csv'
$xp = "*[System[(EventID=220 or EventID=222 or EventID=1010 or EventID=10011 or EventID=807 or EventID=810 or EventID=811)]]"
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('file,time,id,a,b')
Get-ChildItem C:\dev\PC\_evidence\g80sh-*.etl | Where-Object Name -ne 'g80sh-live.etl' | ForEach-Object {
    $f = $_.Name
    $ev = Get-WinEvent -Path $_.FullName -Oldest -FilterXPath $xp -ErrorAction SilentlyContinue
    foreach ($e in $ev) {
        $pr = $e.Properties
        switch ($e.Id) {
            10011 { $a = $pr[0].Value; $b = '{0:X}' -f $pr[1].Value }
            1010  { $a = $pr[0].Value; $b = $pr[1].Value }
            807   { $a = $pr[2].Value; $b = $pr[3].Value }
            default { $a = ($pr | Select-Object -Last 1).Value; $b = $pr[0].Value }
        }
        $rows.Add(('{0},{1},{2},"{3}","{4}"' -f $f, $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss.ffffff'), $e.Id, $a, $b))
    }
    Write-Host "$f $($ev.Count)"
}
[IO.File]::WriteAllLines($out, $rows)
