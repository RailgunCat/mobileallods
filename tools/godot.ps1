param(
    [ValidateSet('Editor', 'Run', 'Check', 'CheckSprites', 'Version')]
    [string]$Mode = 'Editor',
    [string]$GodotExecutable = 'F:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    throw "Godot executable not found: $GodotExecutable"
}
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../godot'))
if ($Mode -eq 'Version') {
    & $GodotExecutable --headless --version | Out-Host
} elseif ($Mode -eq 'CheckSprites') {
    $buildRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../build'))
    New-Item -ItemType Directory -Force $buildRoot | Out-Null
    $spriteLogPath = (Join-Path $buildRoot 'sprite-anchor-check.log').Replace('\', '/')
    & $GodotExecutable --path $projectRoot --log-file $spriteLogPath --quit-after 1000 --script res://tests/sprite_anchor_checks.gd | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Sprite anchor check failed: $LASTEXITCODE" }
    if (Select-String -LiteralPath $spriteLogPath -Pattern 'SCRIPT ERROR:' -Quiet) { throw 'GDScript errors in build/sprite-anchor-check.log' }
    if (-not (Select-String -LiteralPath $spriteLogPath -Pattern '^Sprite anchors: \d+ cases, 0 failures$' -Quiet)) { throw 'Sprite anchor check did not complete' }
} elseif ($Mode -eq 'Check') {
    $buildRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../build'))
    New-Item -ItemType Directory -Force $buildRoot | Out-Null
    & $GodotExecutable --headless --editor --path $projectRoot --import --log-file (Join-Path $buildRoot 'godot-import.log') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed: $LASTEXITCODE" }
    if (Select-String -LiteralPath (Join-Path $buildRoot 'godot-import.log') -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) { throw 'Import errors in build/godot-import.log' }
    $logPath = (Join-Path $buildRoot 'godot-smoke.log').Replace('\', '/')
    & $GodotExecutable --headless --path $projectRoot --log-file (Join-Path $buildRoot 'godot-parse.log').Replace('\', '/') --check-only --script res://scripts/gameplay/gameplay.gd | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "GDScript parse check failed: $LASTEXITCODE" }
    if (Select-String -LiteralPath (Join-Path $buildRoot 'godot-parse.log') -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) { throw 'GDScript errors in build/godot-parse.log' }
    & $GodotExecutable --headless --path $projectRoot --log-file $logPath res://main.tscn -- --smoke-test | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Viewer check failed: $LASTEXITCODE" }
    if (Select-String -LiteralPath $logPath -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) { throw 'Viewer errors in build/godot-smoke.log' }
    & $GodotExecutable --headless --path $projectRoot --log-file (Join-Path $buildRoot 'gameplay-check.log').Replace('\', '/') --quit-after 1000 -- --gameplay-test | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Gameplay check failed: $LASTEXITCODE" }
    if (Select-String -LiteralPath (Join-Path $buildRoot 'gameplay-check.log') -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) { throw 'Gameplay errors in build/gameplay-check.log' }
    if (-not (Select-String -LiteralPath (Join-Path $buildRoot 'gameplay-check.log') -Pattern '^PASS: stages' -Quiet)) { throw 'Gameplay checks did not complete' }
} elseif ($Mode -eq 'Run') {
    & $GodotExecutable --path $projectRoot | Out-Host
} else {
    & $GodotExecutable --editor --path $projectRoot | Out-Host
}
if ($LASTEXITCODE -ne 0) { throw "Godot exited with code $LASTEXITCODE." }
