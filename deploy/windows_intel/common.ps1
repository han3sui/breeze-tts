# Intel Windows 部署脚本共用函数。由 install / start 点源，不要单独执行。

$script:WindowsRoot = $PSScriptRoot
$script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$script:EnvFile = Join-Path $script:WindowsRoot ".env"
$script:EnvExample = Join-Path $script:WindowsRoot ".env.example"
$script:VenvPython = Join-Path $script:RepoRoot ".venv-intel\Scripts\python.exe"

function Write-BreezeLog {
    param([string]$Message, [string]$Level = "INFO")
    $prefix = switch ($Level) {
        "WARN" { "[windows-intel] 警告" }
        "ERROR" { "[windows-intel] 错误" }
        default { "[windows-intel]" }
    }
    Write-Host "$prefix $Message"
}

function Import-BreezeDotEnv {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "缺少 $Path ，请先双击 install.bat"
    }
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }
        $eq = $line.IndexOf("=")
        if ($eq -lt 1) { return }
        $key = $line.Substring(0, $eq).Trim()
        $val = $line.Substring($eq + 1)
        Set-Item -Path "Env:$key" -Value $val
    }
}

function Get-IntelGpuName {
    $names = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Intel|Arc" } |
        Select-Object -ExpandProperty Name
    if ($names) { return ($names -join "; ") }
    return $null
}

function Find-PythonCandidate {
    param([string]$Explicit)
    $candidates = @()
    if ($Explicit) { $candidates += $Explicit }
    $candidates += $script:VenvPython
    foreach ($spec in @("-3.12", "-3.11", "-3.10", "-3")) {
        $launcher = Get-Command py -ErrorAction SilentlyContinue
        if ($launcher) {
            try {
                $resolved = & $launcher.Source $spec -c "import sys; print(sys.executable)" 2>$null
                if ($LASTEXITCODE -eq 0 -and $resolved) { $candidates += $resolved.Trim() }
            }
            catch { }
        }
    }
    foreach ($name in @("python", "python3")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { $candidates += $cmd.Source }
    }
    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    }
    return $null
}

function Test-PythonVersion {
    param([Parameter(Mandatory = $true)][string]$Python)
    $ver = & $Python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
    if ($LASTEXITCODE -ne 0) { throw "无法用 $Python 读取版本" }
    $parts = $ver.Trim().Split(".")
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 10)) {
        throw "需要 Python 3.10 或更高，当前是 $ver"
    }
    return $ver.Trim()
}
