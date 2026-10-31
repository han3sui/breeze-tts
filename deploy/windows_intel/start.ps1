# 前台启动 serve.py（Intel XPU eager）。进程被驱动杀掉，或 XPU 假死
# 后 serve.py 主动退出时，都会自动重启；关窗口或 Ctrl+C 才真正停止。
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Import-BreezeDotEnv -Path $script:EnvFile

$python = $env:PYTHON
if (-not $python -or -not (Test-Path -LiteralPath $python)) {
    $python = Find-PythonCandidate -Explicit $python
}
if (-not $python) { throw "未找到 python，请先双击 install.bat" }
$null = Test-PythonVersion -Python $python

if (-not $env:API_KEY) {
    Write-BreezeLog "API_KEY 为空，接口不鉴权" "WARN"
}

if (-not $env:FAST_ALL) { $env:FAST_ALL = "false" }
if (-not $env:DEVICE) { $env:DEVICE = "xpu" }
if (-not $env:DTYPE) { $env:DTYPE = "bfloat16" }
if (-not $env:TORCHDYNAMO_DISABLE) { $env:TORCHDYNAMO_DISABLE = "1" }

$hfHome = $env:HF_HOME
if (-not $hfHome) { $hfHome = Join-Path $script:WindowsRoot "hf-cache" }
New-Item -ItemType Directory -Force -Path $hfHome | Out-Null
$env:HF_HOME = $hfHome

function Get-EnvInt {
    param([string]$Name, [int]$Default)
    $raw = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
    $parsed = 0
    if ([int]::TryParse($raw, [ref]$parsed) -and $parsed -ge 0) { return $parsed }
    return $Default
}

# RESTART_ON_CRASH=false 可关掉自动拉起，便于盯一次崩溃现场
$restartFlag = $env:RESTART_ON_CRASH
if ([string]::IsNullOrWhiteSpace($restartFlag)) { $restartFlag = "true" }
$restartOnCrash = $restartFlag -notin @("0", "false", "False", "FALSE", "no", "NO")
$minDelaySec = Get-EnvInt "RESTART_DELAY_SEC" 5
$maxDelaySec = Get-EnvInt "RESTART_MAX_DELAY_SEC" 60
$healthySec = Get-EnvInt "RESTART_HEALTHY_SEC" 120
# Windows STATUS_CONTROL_C_EXIT：用户 Ctrl+C，不再拉起
$ctrlCExit = -1073741510

Set-Location -LiteralPath $script:RepoRoot
$servePy = Join-Path $script:RepoRoot "deploy\serve.py"
$crashStreak = 0

while ($true) {
    Write-BreezeLog "starting: $python deploy\serve.py (device=$($env:DEVICE) dtype=$($env:DTYPE))"
    if ($restartOnCrash) {
        Write-BreezeLog "崩溃或 XPU 假死后会自动重启；关此窗口或 Ctrl+C 停止"
    }
    else {
        Write-BreezeLog "关此窗口或 Ctrl+C 停止"
    }

    $startedAt = Get-Date
    & $python $servePy
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 1 }
    $ranSec = [Math]::Max(0, [int]((Get-Date) - $startedAt).TotalSeconds)

    $userStop = ($code -eq 0) -or ($code -eq $ctrlCExit)
    if ($userStop -or -not $restartOnCrash) {
        if ($code -eq 0) {
            Write-BreezeLog "serve.py 已退出"
        }
        else {
            Write-BreezeLog "serve.py 退出，code=$code" "WARN"
        }
        exit $code
    }

    # 跑够一段时间再崩，视为偶发，退避从最短间隔重新计
    if ($ranSec -ge $healthySec) { $crashStreak = 0 }
    $crashStreak++
    $shift = [Math]::Min($crashStreak - 1, 4)
    $delay = [int][Math]::Min($minDelaySec * [Math]::Pow(2, $shift), $maxDelaySec)
    Write-BreezeLog "serve.py 异常退出 code=$code，已运行 ${ranSec}s，${delay}s 后第 $crashStreak 次重启" "WARN"
    Start-Sleep -Seconds $delay
}
