param(
    [string]$Jar = 'allods_360x640_bluetooth_rus.jar',
    [string]$Output = 'analysis/decompiled',
    [string]$JavaExecutable = 'java'
)
$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot 'cfr-0.152.jar'
if (-not (Test-Path -LiteralPath $tool)) {
    Invoke-WebRequest -Uri 'https://www.benf.org/other/cfr/cfr-0.152.jar' -OutFile $tool
}
$expected = 'F686E8F3DED377D7BC87D216A90E9E9512DF4156E75B06C655A16648AE8765B2'
if ((Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash -ne $expected) {
    throw 'CFR download hash differs from the inspected version.'
}
& $JavaExecutable -jar $tool $Jar --outputdir $Output --silent true --renamedupmembers true
if ($LASTEXITCODE -ne 0) { throw 'CFR failed.' }
# CFR's batch pass omitted four small classes in this build. Fill any gaps.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Jar))
try {
    foreach ($entry in $archive.Entries) {
        if (-not $entry.FullName.EndsWith('.class')) { continue }
        $sourcePath = Join-Path $Output ($entry.FullName -replace '\.class$', '.java')
        if (Test-Path -LiteralPath $sourcePath) { continue }
        $bytecodeRoot = [System.IO.Path]::GetFullPath((Join-Path $Output '.bytecode'))
        $classPath = [System.IO.Path]::GetFullPath((Join-Path $bytecodeRoot $entry.FullName))
        if (-not $classPath.StartsWith($bytecodeRoot + [System.IO.Path]::DirectorySeparatorChar)) {
            throw 'Archive class path escapes the output directory.'
        }
        New-Item -ItemType Directory -Force ([System.IO.Path]::GetDirectoryName($classPath)) | Out-Null
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $classPath, $true)
        & $JavaExecutable -jar $tool $classPath --extraclasspath $Jar --outputdir $Output --silent true --renamedupmembers true
        if ($LASTEXITCODE -ne 0) { throw "CFR failed for $($entry.FullName)." }
    }
} finally {
    $archive.Dispose()
}
