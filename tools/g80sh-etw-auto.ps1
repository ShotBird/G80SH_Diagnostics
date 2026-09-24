# g80sh-etw-auto.ps1 — ETW 순환 버퍼를 상시 돌리다가 증상 재발 시 덤프한다.
#
# rev.2 (2026-09-19): 트리거 후에 세션을 시작하면 **화면이 꺼지는 순간**을 놓친다.
#   재열거의 방아쇠가 끄기 명령 자체(DP 링크 다운 → 재훈련 → 대기 EDID)일 수 있으므로
#   세션을 미리 켜 두고 순환 버퍼에 담다가, 트리거가 걸리면 그때까지의 버퍼를 덤프한다.
#
# 관리자 권한 필요. 작업 스케줄러 'G80SH ETW Auto' 로 상주.
param(
    [int]$Captures = 0,   # 0 = 무제한
    [int]$CoolMin  = 30,
    [int]$PostSec  = 150   # 트리거 후 이만큼 더 담고 덤프 (사이클 3회분)
)

$ErrorActionPreference = 'Continue'
$out     = 'C:\dev\1_PC_Setup\_evidence'
$log     = Join-Path $out 'auto.log'
$session = 'G80SH'
$dev     = 'SAM7B0C'

# provider 는 2026-09-18 실측(60초 525,469건)으로 선별. 재선별하지 말 것.
#   {802EC45A-...} DxgKrnl  0x100 = Dxgkrnl_StatusChangeNotify   0/초
#   {9C205A39-...} Kernel-PnP verbose                          273/초
$GUID_DXGK = '{802EC45A-1E99-4B83-9920-87C98277BA9D}'
$GUID_PNP  = '{9C205A39-1250-487D-ABD7-E831C6290539}'

function Log($m) {
    Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8
}

function Start-Session($etl) {
    logman stop $session -ets 2>&1 | Out-Null
    Remove-Item -LiteralPath $etl -Force -ErrorAction SilentlyContinue
    $r = logman create trace $session -ow -o $etl `
        -p $GUID_DXGK 0x100 0xff `
        -nb 64 128 -bs 128 -mode Circular -f bincirc -max 512 -ets 2>&1
    if ($LASTEXITCODE -ne 0) { Log "create FAILED: $r"; return $false }
    $r = logman update trace $session -p $GUID_PNP 0xffffffffffffffff 0xff -ets 2>&1
    if ($LASTEXITCODE -ne 0) { Log "update(PnP) FAILED: $r" }
    Log "session running (circular 512MB) -> $etl"
    return $true
}

function Count-Recent($sec) {
    @(Get-WinEvent -FilterHashtable @{
        LogName   = 'Microsoft-Windows-Kernel-PnP/Device Management'
        Id        = 1010
        StartTime = (Get-Date).AddSeconds(-$sec)
    } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match $dev }).Count
}

New-Item -ItemType Directory -Force -Path $out | Out-Null
Log "auto rev.2 armed (captures=$Captures cool=${CoolMin}m post=${PostSec}s)"

$done = 0
$etl  = Join-Path $out 'g80sh-live.etl'
if (-not (Start-Session $etl)) { Log "abort"; exit 1 }

while ($true) {
    if ((Count-Recent 90) -ge 2) {
        $done++
        $tag = "{0}-{1}" -f (Get-Date -Format 'MMdd-HHmm'), $done
        Log "TRIGGER -> +${PostSec}s 더 담고 덤프 (#$done tag=$tag)"
        Start-Sleep -Seconds $PostSec

        logman stop $session -ets 2>&1 | Out-Null
        $keep = Join-Path $out "g80sh-dxg-$tag.etl"
        Move-Item -LiteralPath $etl -Destination $keep -Force -ErrorAction SilentlyContinue
        if (Test-Path $keep) {
            Log ("etl kept {0} ({1:N0} bytes)" -f (Split-Path $keep -Leaf), (Get-Item $keep).Length)
            & 'C:\dev\1_PC_Setup\tools\g80sh-etw-decode.ps1' -Etl $keep -Tag $tag
        } else { Log "MOVE FAILED - no etl" }

        if ($Captures -gt 0 -and $done -ge $Captures) { Log "auto done ($done)"; break }
        Log "cooling ${CoolMin}m"
        Start-Sleep -Seconds ($CoolMin * 60)
        if (-not (Start-Session $etl)) { Log "restart failed"; break }
    }
    Start-Sleep -Seconds 15
}
logman stop $session -ets 2>&1 | Out-Null
Log "auto stopped"
