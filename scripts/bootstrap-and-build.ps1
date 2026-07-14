param(
    [switch]$Release
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ToolsRoot = Join-Path $ProjectRoot ".tools"
$Downloads = Join-Path $ToolsRoot "downloads"
$JdkArchive = Join-Path $Downloads "jdk17.zip"
$GradleArchive = Join-Path $Downloads "gradle-8.9-bin.zip"
$AndroidCliArchive = Join-Path $Downloads "android-commandline-tools.zip"
$JdkRoot = Join-Path $ToolsRoot "jdk"
$GradleRoot = Join-Path $ToolsRoot "gradle"
$AndroidCliRoot = Join-Path $ToolsRoot "android-commandline-tools"
$AndroidSdkRoot = Join-Path $ToolsRoot "android-sdk"

New-Item -ItemType Directory -Force -Path $Downloads | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-LocalSigningConfig {
    param(
        [Parameter(Mandatory = $true)][string]$SigningRoot,
        [Parameter(Mandatory = $true)][string]$Keystore
    )

    $PropertiesPath = Join-Path $SigningRoot "clockin-release.properties"
    if (Test-Path -LiteralPath $PropertiesPath) {
        $Properties = ConvertFrom-StringData (
            Get-Content -LiteralPath $PropertiesPath -Raw -Encoding UTF8
        )
    } else {
        $KeyAlias = if ($env:CLOCKIN_LOCAL_KEY_ALIAS) {
            $env:CLOCKIN_LOCAL_KEY_ALIAS
        } else {
            "clockin"
        }
        $KeystorePassword = $env:CLOCKIN_LOCAL_KEYSTORE_PASSWORD

        if ([string]::IsNullOrWhiteSpace($KeystorePassword)) {
            if (Test-Path -LiteralPath $Keystore) {
                throw (
                    "Local signing settings are missing. Set " +
                    "CLOCKIN_LOCAL_KEYSTORE_PASSWORD once to migrate the " +
                    "existing keystore."
                )
            }

            $RandomBytes = New-Object byte[] 32
            $Random = [Security.Cryptography.RandomNumberGenerator]::Create()
            try {
                $Random.GetBytes($RandomBytes)
            } finally {
                $Random.Dispose()
            }
            $KeystorePassword = (
                [BitConverter]::ToString($RandomBytes)
            ).Replace("-", "").ToLowerInvariant()
        }

        New-Item -ItemType Directory -Force -Path $SigningRoot | Out-Null
        @(
            "keyAlias=$KeyAlias"
            "keystorePassword=$KeystorePassword"
        ) | Set-Content -LiteralPath $PropertiesPath -Encoding UTF8
        $Properties = @{
            keyAlias = $KeyAlias
            keystorePassword = $KeystorePassword
        }
    }

    if ([string]::IsNullOrWhiteSpace($Properties.keyAlias) -or
        [string]::IsNullOrWhiteSpace($Properties.keystorePassword)) {
        throw "Local signing settings are incomplete: $PropertiesPath"
    }

    return [PSCustomObject]@{
        KeyAlias = $Properties.keyAlias
        KeystorePassword = $Properties.keystorePassword
    }
}

function Test-ZipArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $null = $archive.Entries.Count
        $archive.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Get-Archive {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $existing = Get-Item -LiteralPath $Destination -ErrorAction SilentlyContinue
    if ($null -ne $existing -and $existing.Length -gt 1MB -and
        (Test-ZipArchive -Path $Destination)) {
        Write-Host "Using cached $(Split-Path -Leaf $Destination)"
        return
    }

    if ($null -ne $existing -and $existing.Length -le 1MB) {
        Remove-Item -LiteralPath $Destination -Force
    } elseif ($null -ne $existing) {
        Write-Host "Resuming incomplete $(Split-Path -Leaf $Destination)..."
    }

    Write-Host "Downloading $(Split-Path -Leaf $Destination)..."
    & curl.exe `
        --fail `
        --location `
        --retry 5 `
        --retry-all-errors `
        --retry-delay 2 `
        --connect-timeout 20 `
        --continue-at - `
        --output $Destination `
        $Uri
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed: $Uri"
    }
    if ((Get-Item -LiteralPath $Destination).Length -le 1MB) {
        throw "Downloaded archive is unexpectedly small: $Destination"
    }
    if (-not (Test-ZipArchive -Path $Destination)) {
        throw "Downloaded archive failed ZIP validation: $Destination"
    }
}

Get-Archive `
    -Uri "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse" `
    -Destination $JdkArchive
Get-Archive `
    -Uri "https://services.gradle.org/distributions/gradle-8.9-bin.zip" `
    -Destination $GradleArchive
Get-Archive `
    -Uri "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" `
    -Destination $AndroidCliArchive

if (-not (Get-ChildItem -LiteralPath $JdkRoot -Filter java.exe -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1)) {
    New-Item -ItemType Directory -Force -Path $JdkRoot | Out-Null
    Expand-Archive -LiteralPath $JdkArchive -DestinationPath $JdkRoot -Force
}
if (-not (Test-Path -LiteralPath (Join-Path $GradleRoot "gradle-8.9\bin\gradle.bat"))) {
    New-Item -ItemType Directory -Force -Path $GradleRoot | Out-Null
    Expand-Archive -LiteralPath $GradleArchive -DestinationPath $GradleRoot -Force
}
if (-not (Test-Path -LiteralPath (Join-Path $AndroidCliRoot "cmdline-tools\bin\sdkmanager.bat"))) {
    New-Item -ItemType Directory -Force -Path $AndroidCliRoot | Out-Null
    Expand-Archive -LiteralPath $AndroidCliArchive -DestinationPath $AndroidCliRoot -Force
}

$JavaHome = Get-ChildItem -LiteralPath $JdkRoot -Directory |
    Select-Object -First 1 -ExpandProperty FullName
$GradleHome = Get-ChildItem -LiteralPath $GradleRoot -Directory |
    Select-Object -First 1 -ExpandProperty FullName
$SdkManager = Join-Path $AndroidCliRoot "cmdline-tools\bin\sdkmanager.bat"
$Gradle = Join-Path $GradleHome "bin\gradle.bat"

if (-not (Test-Path -LiteralPath $JavaHome)) {
    throw "JDK extraction failed."
}
if (-not (Test-Path -LiteralPath $SdkManager)) {
    throw "Android command-line tools extraction failed."
}
if (-not (Test-Path -LiteralPath $Gradle)) {
    throw "Gradle extraction failed."
}

$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdkRoot
$env:ANDROID_SDK_ROOT = $AndroidSdkRoot
$env:Path = "$JavaHome\bin;$AndroidSdkRoot\platform-tools;$env:Path"

New-Item -ItemType Directory -Force -Path $AndroidSdkRoot | Out-Null

Write-Host "Accepting Android SDK licenses..."
$licenseAnswers = (1..200 | ForEach-Object { "y" }) -join "`n"
$licenseAnswers | & $SdkManager "--sdk_root=$AndroidSdkRoot" --licenses | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Android SDK license acceptance failed with exit code $LASTEXITCODE."
}

Write-Host "Installing Android SDK 35..."
$sdkPackages = @(
    @{
        Name = "platform-tools"
        Expected = (Join-Path $AndroidSdkRoot "platform-tools\adb.exe")
    },
    @{
        Name = "platforms;android-35"
        Expected = (Join-Path $AndroidSdkRoot "platforms\android-35\android.jar")
    },
    @{
        Name = "build-tools;35.0.0"
        Expected = (Join-Path $AndroidSdkRoot "build-tools\35.0.0\aapt2.exe")
    }
)
foreach ($package in $sdkPackages) {
    if (Test-Path -LiteralPath $package.Expected) {
        Write-Host "Using installed $($package.Name)"
        continue
    }
    Write-Host "Installing $($package.Name)..."
    & $SdkManager `
        "--sdk_root=$AndroidSdkRoot" `
        --verbose `
        $package.Name
    if ($LASTEXITCODE -ne 0) {
        throw "Android SDK package installation failed: $($package.Name)"
    }
    if (-not (Test-Path -LiteralPath $package.Expected)) {
        throw "Android SDK package did not produce $($package.Expected)"
    }
}

$BuildProjectRoot = $ProjectRoot
$BuildGradle = $Gradle
$BuildJavaHome = $JavaHome
$BuildAndroidSdkRoot = $AndroidSdkRoot
$SubstDrive = $null
$AppBuildFile = Join-Path $ProjectRoot "app\build.gradle"
$AppBuildText = Get-Content -LiteralPath $AppBuildFile -Raw
if ($AppBuildText -notmatch 'versionName\s+"([^"]+)"') {
    throw "Could not read versionName from $AppBuildFile"
}
$ReleaseApkName = "check-in-$($Matches[1]).apk"

if ($ProjectRoot -match "[^\x00-\x7F]") {
    foreach ($driveLetter in @("W:", "V:", "U:", "T:", "S:", "R:")) {
        if (Test-Path -LiteralPath "$driveLetter\") {
            continue
        }
        & subst.exe $driveLetter $ProjectRoot
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath "$driveLetter\")) {
            $SubstDrive = $driveLetter
            $BuildProjectRoot = "$driveLetter\"
            $BuildGradle = Join-Path $BuildProjectRoot (
                $Gradle.Substring($ProjectRoot.Length).TrimStart("\")
            )
            $BuildJavaHome = Join-Path $BuildProjectRoot (
                $JavaHome.Substring($ProjectRoot.Length).TrimStart("\")
            )
            $BuildAndroidSdkRoot = Join-Path $BuildProjectRoot (
                $AndroidSdkRoot.Substring($ProjectRoot.Length).TrimStart("\")
            )
            Write-Host "Using ASCII build path $BuildProjectRoot"
            break
        }
    }
    if ($null -eq $SubstDrive) {
        throw "Could not create an ASCII drive mapping for the project path."
    }
}

$env:JAVA_HOME = $BuildJavaHome
$env:ANDROID_HOME = $BuildAndroidSdkRoot
$env:ANDROID_SDK_ROOT = $BuildAndroidSdkRoot
$env:Path = "$BuildJavaHome\bin;$BuildAndroidSdkRoot\platform-tools;$env:Path"

Push-Location $BuildProjectRoot
try {
    & $BuildGradle --stop | Out-Host

    if (-not (Test-Path -LiteralPath (Join-Path $BuildProjectRoot "gradlew.bat"))) {
        Write-Host "Generating Gradle wrapper..."
        & $BuildGradle --no-daemon wrapper --gradle-version 8.9
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle wrapper generation failed with exit code $LASTEXITCODE."
        }
    }

    $Task = if ($Release) { ":app:assembleRelease" } else { ":app:assembleDebug" }
    Write-Host "Running $Task..."
    & $BuildGradle --no-daemon $Task
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed with exit code $LASTEXITCODE."
    }

    if ($Release) {
        $SigningRoot = Join-Path $BuildProjectRoot ".signing"
        $Keystore = Join-Path $SigningRoot "clockin-release.p12"
        $UnsignedApk = Join-Path $BuildProjectRoot (
            "app\build\outputs\apk\release\app-release-unsigned.apk"
        )
        $SignedApk = Join-Path $BuildProjectRoot (
            "app\build\outputs\apk\release\$ReleaseApkName"
        )
        $Keytool = Join-Path $BuildJavaHome "bin\keytool.exe"
        $ApkSigner = Join-Path $BuildAndroidSdkRoot (
            "build-tools\35.0.0\apksigner.bat"
        )
        $SigningConfig = Get-LocalSigningConfig `
            -SigningRoot $SigningRoot `
            -Keystore $Keystore
        $KeyAlias = $SigningConfig.KeyAlias
        $KeystorePassword = $SigningConfig.KeystorePassword

        if (-not (Test-Path -LiteralPath $UnsignedApk)) {
            throw "Release build did not produce $UnsignedApk"
        }
        New-Item -ItemType Directory -Force -Path $SigningRoot | Out-Null
        if (-not (Test-Path -LiteralPath $Keystore)) {
            Write-Host "Generating the local release signing key..."
            & $Keytool `
                -genkeypair `
                -storetype PKCS12 `
                -keystore $Keystore `
                -storepass $KeystorePassword `
                -keypass $KeystorePassword `
                -alias $KeyAlias `
                -keyalg RSA `
                -keysize 2048 `
                -validity 36500 `
                -dname "CN=ClockIn Assistant, O=Local Build, C=CN"
            if ($LASTEXITCODE -ne 0) {
                throw "Release key generation failed with exit code $LASTEXITCODE."
            }
        }
        if (Test-Path -LiteralPath $SignedApk) {
            Remove-Item -LiteralPath $SignedApk -Force
        }
        Write-Host "Signing release APK..."
        & $ApkSigner `
            sign `
            --ks $Keystore `
            --ks-key-alias $KeyAlias `
            --ks-pass "pass:$KeystorePassword" `
            --key-pass "pass:$KeystorePassword" `
            --out $SignedApk `
            $UnsignedApk
        if ($LASTEXITCODE -ne 0) {
            throw "Release APK signing failed with exit code $LASTEXITCODE."
        }
        & $ApkSigner verify --verbose --print-certs $SignedApk
        if ($LASTEXITCODE -ne 0) {
            throw "Release APK verification failed with exit code $LASTEXITCODE."
        }
    }
} finally {
    Pop-Location
    if ($null -ne $SubstDrive) {
        & subst.exe $SubstDrive /D
    }
}

$Apk = if ($Release) {
    Join-Path $ProjectRoot "app\build\outputs\apk\release\$ReleaseApkName"
} else {
    Join-Path $ProjectRoot "app\build\outputs\apk\debug\app-debug.apk"
}
if (-not (Test-Path -LiteralPath $Apk)) {
    throw "Build finished without producing the expected APK: $Apk"
}

Get-Item -LiteralPath $Apk |
    Select-Object FullName, Length, LastWriteTime |
    Format-List
