# Yiora 发版前回归冒烟基线:重置数据卷 → 起全部服务 → 依次跑各套件
# 用法(在 server/ 目录): powershell -ExecutionPolicy Bypass -File scripts/smoke.ps1
#   Linux/CI(pwsh 7): pwsh -File scripts/smoke.ps1
# 套件有依赖顺序:community 注册账号 → software/m3 复用账号 → mall 复用忧珠
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 与 pwsh 7(CI/Linux)双兼容:子套件用当前引擎再起进程
$psBin = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    Write-Output "== reset compose (down -v && up --build) =="
    # docker 的进度输出走 stderr,EAP=Stop 下会误报 NativeCommandError,这段放宽
    $ErrorActionPreference = 'Continue'
    docker compose down -v *> $null
    docker compose up -d --build *> $null
    if ($LASTEXITCODE -ne 0) { throw "compose up failed" }
    $ErrorActionPreference = 'Stop'

    Write-Output "== wait for api ready =="
    $deadline = (Get-Date).AddSeconds(120)
    while ($true) {
        try {
            $r = Invoke-RestMethod "http://localhost:8888/api/v1/circles" -TimeoutSec 3
            if ($r.code -eq 0) { break }
        } catch { }
        if ((Get-Date) -gt $deadline) { throw "api not ready in 120s" }
        Start-Sleep -Seconds 3
    }

    Write-Output "== wait for ws gateway ready =="
    while ($true) {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        try {
            $tcp.Connect("127.0.0.1", 8889)
            if ($tcp.Connected) { $tcp.Close(); break }
        } catch { } finally { $tcp.Dispose() }
        if ((Get-Date) -gt $deadline) { throw "ws not ready in 120s" }
        Start-Sleep -Seconds 2
    }

    $suites = @(
        @{name = "community"; file = "scripts/smoke-community.ps1"; sentinel = "SMOKE_DONE"},
        @{name = "software";  file = "scripts/smoke-software.ps1";  sentinel = "SOFT_SMOKE_DONE"},
        @{name = "m3";        file = "scripts/smoke-m3.ps1";        sentinel = "M3_SMOKE_DONE"},
        @{name = "mall";      file = "scripts/smoke-mall.ps1";      sentinel = "MALL_SMOKE_DONE"},
        @{name = "paid-ai";   file = "scripts/smoke-paid-ai.ps1";   sentinel = "PAID_AI_SMOKE_DONE"},
        @{name = "content";   file = "scripts/smoke-content.ps1";   sentinel = "CONTENT_SMOKE_DONE"},
        @{name = "account";   file = "scripts/smoke-account.ps1";   sentinel = "ACCOUNT_SMOKE_DONE"},
        @{name = "p1";        file = "scripts/smoke-p1.ps1";        sentinel = "P1_SMOKE_DONE"},
        @{name = "p2";        file = "scripts/smoke-p2.ps1";        sentinel = "P2_SMOKE_DONE"},
        @{name = "admin";     file = "scripts/smoke-admin.ps1";     sentinel = "ADMIN_SMOKE_DONE"}
    )
    $failed = @()
    foreach ($s in $suites) {
        Write-Output "== suite: $($s.name) =="
        $out = & $psBin -ExecutionPolicy Bypass -File $s.file 2>&1 | Out-String
        Write-Output $out
        if ($out -notmatch $s.sentinel) { $failed += $s.name }
    }

    if ($failed.Count -gt 0) {
        Write-Output ("SMOKE RESULT: FAILED -> " + ($failed -join ', '))
        exit 1
    }
    Write-Output "SMOKE RESULT: ALL PASSED"
} finally {
    Pop-Location
}
