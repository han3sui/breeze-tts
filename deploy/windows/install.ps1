# Windows 安装：创建 venv、装 CUDA 版 PyTorch 与依赖、生成 .env（不装 flash-attn）
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Python = $env:PYTHON,
    [switch]$SkipVenv,
    [switch]$SkipHfMirror,
    [string]$TorchIndexUrl = "https://download.pytorch.org/whl/cu128"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$smi = Get-NvidiaSmi
if ($smi) {
    Write-BreezeLog ("GPU: " + ((& $smi --query-gpu=name,memory.total --format=csv,noheader) -join "; "))
}
else {
    Write-BreezeLog "未检测到 nvidia-smi，请先安装 NVIDIA 驱动" "WARN"
}

$python = Find-PythonCandidate -Explicit $Python
if (-not $python) {
    throw "未找到 Python。请安装 3.10+ 后重试，或用 -Python 指定路径。"
}
$pyVer = Test-PythonVersion -Python $python
Write-BreezeLog "repo=$($script:RepoRoot) python=$python ($pyVer)"

if (-not $SkipVenv) {
    $venvDir = Join-Path $script:RepoRoot ".venv"
    $venvPython = Join-Path $venvDir "Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $venvPython)) {
        Write-BreezeLog "创建虚拟环境 $venvDir"
        & $python -m venv $venvDir
        if ($LASTEXITCODE -ne 0) { throw "创建 venv 失败" }
    }
    $python = $venvPython
    $null = Test-PythonVersion -Python $python
}

Write-BreezeLog "升级 pip"
& $python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "升级 pip 失败" }

# 先钉 CUDA 轮子；requirements.txt 可能再拉一次 torch，装完后再钉回去
Write-BreezeLog "安装 torch==2.9.1 + CUDA（$TorchIndexUrl）"
& $python -m pip install torch==2.9.1 torchaudio==2.9.1 --index-url $TorchIndexUrl
if ($LASTEXITCODE -ne 0) { throw "安装 CUDA 版 PyTorch 失败，请核对驱动是否支持 CUDA 12.8" }

Write-BreezeLog "安装 requirements.txt（不装 flash-attn）"
& $python -m pip install -r (Join-Path $script:RepoRoot "requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "安装 requirements.txt 失败" }

Write-BreezeLog "重新钉 CUDA 版 PyTorch，避免被 PyPI CPU 轮子覆盖"
& $python -m pip install torch==2.9.1 torchaudio==2.9.1 --index-url $TorchIndexUrl
if ($LASTEXITCODE -ne 0) { throw "重新钉 PyTorch 失败" }

& $python -m pip install psutil nvidia-ml-py
if ($LASTEXITCODE -ne 0) { throw "安装 psutil / nvidia-ml-py 失败" }

$cudaOk = & $python -c "import torch; print('1' if torch.cuda.is_available() else '0'); print(torch.__version__); print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else '')"
if ($LASTEXITCODE -ne 0) { throw "导入 torch 失败" }
$cudaLines = @($cudaOk)
if ($cudaLines[0] -ne "1") {
    throw "torch.cuda.is_available() 为 False（$($cudaLines[1])）。请确认装的是 CUDA 轮子，且 NVIDIA 驱动可用。"
}
Write-BreezeLog "CUDA 可用: $($cudaLines[1]) / $($cudaLines[2])"

$hfHome = Join-Path $script:WindowsRoot "hf-cache"
New-Item -ItemType Directory -Force -Path $hfHome | Out-Null

if (-not (Test-Path -LiteralPath $script:EnvFile)) {
    Copy-Item -LiteralPath $script:EnvExample -Destination $script:EnvFile
    $apiKey = & $python -c "import secrets; print(secrets.token_urlsafe(24))"
    $fastAll = "true"
    $memMb = Get-GpuMemoryMb
    if ($memMb -and $memMb -lt 20000) { $fastAll = "false" }
    $hfEndpoint = "https://hf-mirror.com"
    if ($SkipHfMirror) { $hfEndpoint = "" }

    $text = [System.IO.File]::ReadAllText($script:EnvFile)
    $text = $text.Replace("API_KEY=`r`n", "API_KEY=$apiKey`r`n")
    $text = $text.Replace("API_KEY=`n", "API_KEY=$apiKey`n")
    $text = $text.Replace("HF_HOME=`r`n", "HF_HOME=$hfHome`r`n")
    $text = $text.Replace("HF_HOME=`n", "HF_HOME=$hfHome`n")
    $text = $text.Replace("FAST_ALL=true", "FAST_ALL=$fastAll")
    $text = $text.Replace("HF_ENDPOINT=https://hf-mirror.com", "HF_ENDPOINT=$hfEndpoint")
    $text = $text.Replace("PYTHON=`r`n", "PYTHON=$python`r`n")
    $text = $text.Replace("PYTHON=`n", "PYTHON=$python`n")
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($script:EnvFile, $text, $utf8)

    Write-BreezeLog "已写入 $($script:EnvFile)"
    Write-BreezeLog "API_KEY=$apiKey"
    Write-BreezeLog "FAST_ALL=$fastAll"
    Write-BreezeLog "PYTHON=$python"
}
else {
    Write-BreezeLog "已存在 $($script:EnvFile) ，未覆盖"
}

Write-BreezeLog "安装完成。之后双击 start.bat 即可启动，关窗口停止。"
