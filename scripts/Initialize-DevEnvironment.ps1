[CmdletBinding(SupportsShouldProcess)]
param([string]$Path = (Join-Path $PSScriptRoot '..\.venv'))

$ErrorActionPreference = 'Stop'
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw 'Python is optional, but is required to create the requested virtual environment.' }
if ($PSCmdlet.ShouldProcess($Path, 'Create Python virtual environment and install development dependencies')) {
    python -m venv $Path
    $python = if ($IsWindows) { Join-Path $Path 'Scripts\python.exe' } else { Join-Path $Path 'bin/python' }
    & $python -m pip install --disable-pip-version-check -r (Join-Path $PSScriptRoot '..\requirements-dev.txt')
}

