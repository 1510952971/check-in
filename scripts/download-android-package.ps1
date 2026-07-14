param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$Output,
    [Parameter(Mandatory = $true)][long]$Size,
    [Parameter(Mandatory = $true)][string]$Sha1,
    [int]$Segments = 8
)

$ErrorActionPreference = "Stop"
$Output = [System.IO.Path]::GetFullPath($Output)
$OutputDirectory = Split-Path -Parent $Output
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

if (Test-Path -LiteralPath $Output) {
    $existingHash = (Get-FileHash -Algorithm SHA1 -LiteralPath $Output).Hash
    if ((Get-Item -LiteralPath $Output).Length -eq $Size -and
            $existingHash -eq $Sha1) {
        Write-Host "Using verified $(Split-Path -Leaf $Output)"
        exit 0
    }
    Remove-Item -LiteralPath $Output -Force
}

$chunkSize = [long][Math]::Ceiling($Size / $Segments)
$parts = @()
$processes = @()

for ($index = 0; $index -lt $Segments; $index++) {
    $start = $index * $chunkSize
    if ($start -ge $Size) {
        break
    }
    $end = [Math]::Min($Size - 1, $start + $chunkSize - 1)
    $partPath = "$Output.part$($index.ToString('00'))"
    $expectedPartSize = $end - $start + 1
    $parts += [pscustomobject]@{
        Path = $partPath
        Start = $start
        End = $end
        Size = $expectedPartSize
    }

    if ((Test-Path -LiteralPath $partPath) -and
            (Get-Item -LiteralPath $partPath).Length -eq $expectedPartSize) {
        continue
    }
    if (Test-Path -LiteralPath $partPath) {
        Remove-Item -LiteralPath $partPath -Force
    }

    $arguments = @(
        "--fail",
        "--location",
        "--retry", "5",
        "--retry-all-errors",
        "--connect-timeout", "20",
        "--range", "$start-$end",
        "--output", $partPath,
        $Uri
    )
    $processes += Start-Process `
        -FilePath "curl.exe" `
        -ArgumentList $arguments `
        -PassThru `
        -WindowStyle Hidden
}

while (@($processes | Where-Object { -not $_.HasExited }).Count -gt 0) {
    $downloaded = 0L
    foreach ($part in $parts) {
        if (Test-Path -LiteralPath $part.Path) {
            $downloaded += (Get-Item -LiteralPath $part.Path).Length
        }
    }
    $percent = [Math]::Min(100, [Math]::Round(($downloaded / $Size) * 100, 1))
    Write-Host "Downloaded $percent% ($([Math]::Round($downloaded / 1MB, 1)) MB)"
    Start-Sleep -Seconds 5
    foreach ($process in $processes) {
        $process.Refresh()
    }
}

foreach ($process in $processes) {
    if ($process.ExitCode -ne 0) {
        throw "curl process $($process.Id) failed with exit code $($process.ExitCode)."
    }
}
foreach ($part in $parts) {
    if (-not (Test-Path -LiteralPath $part.Path) -or
            (Get-Item -LiteralPath $part.Path).Length -ne $part.Size) {
        throw "Range download is incomplete: $($part.Path)"
    }
}

$outputStream = [System.IO.File]::Open(
    $Output,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None
)
try {
    foreach ($part in $parts) {
        $inputStream = [System.IO.File]::OpenRead($part.Path)
        try {
            $inputStream.CopyTo($outputStream)
        } finally {
            $inputStream.Dispose()
        }
    }
} finally {
    $outputStream.Dispose()
}

if ((Get-Item -LiteralPath $Output).Length -ne $Size) {
    throw "Combined file size does not match the repository manifest."
}
$actualSha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $Output).Hash
if ($actualSha1 -ne $Sha1) {
    throw "SHA-1 mismatch. Expected $Sha1, got $actualSha1."
}

foreach ($part in $parts) {
    Remove-Item -LiteralPath $part.Path -Force
}

Get-Item -LiteralPath $Output |
    Select-Object FullName, Length, LastWriteTime |
    Format-List
