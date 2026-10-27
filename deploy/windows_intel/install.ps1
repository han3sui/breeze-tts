# Intel Arc 安装：创建 .venv-intel、装 XPU 版 PyTorch、生成 .env（不装 flash-attn，FAST_ALL 固定关闭）
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Python = $env:PYTHON,
    [switch]$SkipVenv,
    [switch]$SkipHfMirror,
    [string]$TorchIndexUrl = "https://download.pytorch.org/whl/xpu"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$gpuName = Get-IntelGpuName
if ($gpuName) {
    Write-BreezeLog "GPU: $gpuName"
}
else {
    Write-BreezeLog "未检测到 Intel/Arc 显卡，请先安装 Intel 显卡驱动" "WARN"
}

$python = Find-PythonCandidate -Explicit $Python
if (-not $python) {
    throw "未找到 Python。请安装 3.10+ 后重试，或用 -Python 指定路径。"
}
$pyVer = Test-PythonVersion -Python $python
Write-BreezeLog "repo=$($script:RepoRoot) python=$python ($pyVer)"

if (-not $SkipVenv) {
    $venvDir = Join-Path $script:RepoRoot ".venv-intel"
    if (-not (Test-Path -LiteralPath $script:VenvPython)) {
        Write-BreezeLog "创建虚拟环境 $venvDir（与 NVIDIA 的 .venv 分开）"
        & $python -m venv $venvDir
        if ($LASTEXITCODE -ne 0) { throw "创建 venv 失败" }
    }
    $python = $script:VenvPython
    $null = Test-PythonVersion -Python $python
}

Write-BreezeLog "升级 pip"
& $python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "升级 pip 失败" }

Write-BreezeLog "安装 torch==2.9.1 + XPU（$TorchIndexUrl）"
& $python -m pip install torch==2.9.1 torchaudio==2.9.1 --index-url $TorchIndexUrl
if ($LASTEXITCODE -ne 0) { throw "安装 XPU 版 PyTorch 失败，请核对 Intel 驱动与 PyTorch XPU 轮子" }

Write-BreezeLog "安装 requirements.txt（不装 flash-attn）"
# qwen-tts 未钉死 gradio，pip 会回溯几十个 30MB 包；推理只用 tokenizer，钉一个可用版本
& $python -m pip install "gradio==5.49.1"
if ($LASTEXITCODE -ne 0) { throw "安装 gradio 失败" }
& $python -m pip install -r (Join-Path $script:RepoRoot "requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "安装 requirements.txt 失败" }

Write-BreezeLog "重新钉 XPU 版 PyTorch，避免被 PyPI CPU/CUDA 轮子覆盖"
& $python -m pip install torch==2.9.1 torchaudio==2.9.1 --index-url $TorchIndexUrl
if ($LASTEXITCODE -ne 0) { throw "重新钉 PyTorch 失败" }

& $python -m pip install psutil
if ($LASTEXITCODE -ne 0) { throw "安装 psutil 失败" }

$xpuOk = & $python -c "import torch; xpu=getattr(torch,'xpu',None); print('1' if (xpu and xpu.is_available()) else '0'); print(torch.__version__); print(xpu.get_device_name(0) if (xpu and xpu.is_available()) else '')"
if ($LASTEXITCODE -ne 0) { throw "导入 torch 失败" }
$xpuLines = @($xpuOk)
if ($xpuLines[0] -ne "1") {
    throw "torch.xpu.is_available() 为 False（$($xpuLines[1])）。请确认装的是 XPU 轮子，且 Intel 显卡驱动可用。"
}
Write-BreezeLog "XPU 可用: $($xpuLines[1]) / $($xpuLines[2])"

$hfHome = Join-Path $script:WindowsRoot "hf-cache"
New-Item -ItemType Directory -Force -Path $hfHome | Out-Null

if (-not (Test-Path -LiteralPath $script:EnvFile)) {
    Copy-Item -LiteralPath $script:EnvExample -Destination $script:EnvFile
    $apiKey = & $python -c "import secrets; print(secrets.token_urlsafe(24))"
    $hfEndpoint = "https://hf-mirror.com"
    if ($SkipHfMirror) { $hfEndpoint = "" }

    $text = [System.IO.File]::ReadAllText($script:EnvFile)
    $text = $text.Replace("API_KEY=`r`n", "API_KEY=$apiKey`r`n")
    $text = $text.Replace("API_KEY=`n", "API_KEY=$apiKey`n")
    $text = $text.Replace("HF_HOME=`r`n", "HF_HOME=$hfHome`r`n")
    $text = $text.Replace("HF_HOME=`n", "HF_HOME=$hfHome`n")
    $text = $text.Replace("HF_ENDPOINT=https://hf-mirror.com", "HF_ENDPOINT=$hfEndpoint")
    $text = $text.Replace("PYTHON=`r`n", "PYTHON=$python`r`n")
    $text = $text.Replace("PYTHON=`n", "PYTHON=$python`n")
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($script:EnvFile, $text, $utf8)

    Write-BreezeLog "已写入 $($script:EnvFile)"
    Write-BreezeLog "API_KEY=$apiKey"
    Write-BreezeLog "FAST_ALL=false DEVICE=xpu"
    Write-BreezeLog "PYTHON=$python"
}
else {
    Write-BreezeLog "已存在 $($script:EnvFile) ，未覆盖"
}

Write-BreezeLog "安装完成。之后双击 start.bat 即可启动，关窗口停止。"
Write-BreezeLog "单条合成: .venv-intel\Scripts\python.exe infer.py <模型目录> --text `"你好`" --output out.wav"
