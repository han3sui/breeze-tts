# 前台启动 serve.py，关窗口或 Ctrl+C 即停
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

# 关掉 dynamo，避免 torch 2.9.1 inductor 预热报错；CUDA Graph 仍可用
if (-not $env:TORCHDYNAMO_DISABLE) { $env:TORCHDYNAMO_DISABLE = "1" }

$hfHome = $env:HF_HOME
if (-not $hfHome) { $hfHome = Join-Path $script:WindowsRoot "hf-cache" }
New-Item -ItemType Directory -Force -Path $hfHome | Out-Null
$env:HF_HOME = $hfHome

Set-Location -LiteralPath $script:RepoRoot
Write-BreezeLog "starting: $python deploy\serve.py"
Write-BreezeLog "关此窗口或 Ctrl+C 停止"
& $python (Join-Path $script:RepoRoot "deploy\serve.py")
exit $LASTEXITCODE
