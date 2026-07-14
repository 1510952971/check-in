Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:CredentialPrefix = "AndroidSigningManager"
$script:SchemaVersion = 1
$script:PortableVaultSchemaVersion = 1
$script:PortableVaultFormat = "AndroidSigningManagerPortableVault"
$script:PortableBackupExtension = ".asmvault.gpg"

if (-not ("AndroidSigningManager.NativeCredential" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace AndroidSigningManager
{
    public static class NativeCredential
    {
        private const int CredTypeGeneric = 1;
        private const int CredPersistLocalMachine = 2;
        private const int ErrorNotFound = 1168;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct Credential
        {
            public int Flags;
            public int Type;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string TargetName;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string Comment;
            public long LastWritten;
            public int CredentialBlobSize;
            public IntPtr CredentialBlob;
            public int Persist;
            public int AttributeCount;
            public IntPtr Attributes;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string TargetAlias;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string UserName;
        }

        [DllImport("advapi32.dll", EntryPoint = "CredWriteW",
            CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWrite(
            ref Credential userCredential,
            int flags
        );

        [DllImport("advapi32.dll", EntryPoint = "CredReadW",
            CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(
            string target,
            int type,
            int flags,
            out IntPtr credentialPtr
        );

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW",
            CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDelete(
            string target,
            int type,
            int flags
        );

        [DllImport("advapi32.dll", SetLastError = false)]
        private static extern void CredFree(IntPtr buffer);

        public static void Write(
            string target,
            string userName,
            string secret
        )
        {
            byte[] bytes = Encoding.UTF8.GetBytes(secret);
            IntPtr blob = Marshal.AllocCoTaskMem(bytes.Length);
            try
            {
                Marshal.Copy(bytes, 0, blob, bytes.Length);
                Credential credential = new Credential
                {
                    Flags = 0,
                    Type = CredTypeGeneric,
                    TargetName = target,
                    Comment = "Android Signing Manager",
                    CredentialBlobSize = bytes.Length,
                    CredentialBlob = blob,
                    Persist = CredPersistLocalMachine,
                    AttributeCount = 0,
                    Attributes = IntPtr.Zero,
                    TargetAlias = null,
                    UserName = userName
                };
                if (!CredWrite(ref credential, 0))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
            }
            finally
            {
                for (int index = 0; index < bytes.Length; index++)
                {
                    bytes[index] = 0;
                    Marshal.WriteByte(blob, index, 0);
                }
                Marshal.FreeCoTaskMem(blob);
            }
        }

        public static string Read(string target)
        {
            IntPtr credentialPtr;
            if (!CredRead(target, CredTypeGeneric, 0, out credentialPtr))
            {
                int error = Marshal.GetLastWin32Error();
                if (error == ErrorNotFound)
                {
                    return null;
                }
                throw new Win32Exception(error);
            }

            try
            {
                Credential credential = (Credential)Marshal.PtrToStructure(
                    credentialPtr,
                    typeof(Credential)
                );
                byte[] bytes = new byte[credential.CredentialBlobSize];
                Marshal.Copy(
                    credential.CredentialBlob,
                    bytes,
                    0,
                    bytes.Length
                );
                try
                {
                    return Encoding.UTF8.GetString(bytes);
                }
                finally
                {
                    Array.Clear(bytes, 0, bytes.Length);
                }
            }
            finally
            {
                CredFree(credentialPtr);
            }
        }

        public static bool Delete(string target)
        {
            if (CredDelete(target, CredTypeGeneric, 0))
            {
                return true;
            }
            int error = Marshal.GetLastWin32Error();
            if (error == ErrorNotFound)
            {
                return false;
            }
            throw new Win32Exception(error);
        }
    }
}
"@
}

function Get-DefaultSigningVaultRoot {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_SIGNING_VAULT)) {
        return [IO.Path]::GetFullPath($env:ANDROID_SIGNING_VAULT)
    }

    $documents = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::MyDocuments
    )
    return Join-Path $documents "Android-Signing-Vault"
}

function Initialize-SigningVault {
    [CmdletBinding()]
    param(
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    $fullRoot = [IO.Path]::GetFullPath($VaultRoot)
    New-Item -ItemType Directory -Force -Path $fullRoot | Out-Null
    return $fullRoot
}

function Resolve-PortableDestinationPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $candidate = $Path.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw "Select or enter a backup destination folder."
    }
    if ($candidate.StartsWith("::")) {
        throw (
            "Select a real folder, not This PC, Network, or another " +
            "Windows virtual location."
        )
    }
    if ($candidate -match '^smb://') {
        try {
            $uri = New-Object Uri($candidate)
        } catch {
            throw "The SMB address is invalid."
        }
        $relativePath = [Uri]::UnescapeDataString(
            $uri.AbsolutePath.TrimStart("/")
        ).Replace("/", "\")
        if ([string]::IsNullOrWhiteSpace($uri.Host) -or
            [string]::IsNullOrWhiteSpace($relativePath)) {
            throw (
                "An SMB address must include a server and shared folder, " +
                "for example smb://nas/backup."
            )
        }
        $candidate = "\\$($uri.Host)\$relativePath"
    } elseif ($candidate -match '^file://') {
        try {
            $candidate = (New-Object Uri($candidate)).LocalPath
        } catch {
            throw "The file address is invalid."
        }
    } elseif ($candidate -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
        throw (
            "Use a Windows path, UNC path, file:// address, or smb:// " +
            "address for the backup destination."
        )
    }

    if (-not [IO.Path]::IsPathRooted($candidate)) {
        throw (
            "Use an absolute path such as E:\Android-Backup or " +
            "\\NAS\Backup\Android."
        )
    }
    try {
        return [IO.Path]::GetFullPath($candidate)
    } catch {
        throw "The backup destination path format is invalid."
    }
}

function Get-CredentialTarget {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId
    )

    return "$($script:CredentialPrefix):$PackageId"
}

function Test-PackageId {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId
    )

    return $PackageId -match (
        "^[A-Za-z][A-Za-z0-9_]*" +
        "(\.[A-Za-z][A-Za-z0-9_]*)+$"
    )
}

function Test-RepositoryName {
    param(
        [string]$Repository
    )

    if ([string]::IsNullOrWhiteSpace($Repository)) {
        return $true
    }
    return $Repository -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"
}

function Test-SecretPrefix {
    param(
        [Parameter(Mandatory = $true)][string]$SecretPrefix
    )

    return $SecretPrefix -match "^[A-Z][A-Z0-9_]*$"
}

function Get-AppDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$VaultRoot,
        [Parameter(Mandatory = $true)][string]$PackageId
    )

    if (-not (Test-PackageId -PackageId $PackageId)) {
        throw "Invalid Android package id: $PackageId"
    }
    return Join-Path ([IO.Path]::GetFullPath($VaultRoot)) $PackageId
}

function Get-MetadataPath {
    param(
        [Parameter(Mandatory = $true)][string]$AppDirectory
    )

    return Join-Path $AppDirectory "metadata.json"
}

function Read-SigningMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$AppDirectory
    )

    $metadataPath = Get-MetadataPath -AppDirectory $AppDirectory
    if (-not (Test-Path -LiteralPath $metadataPath)) {
        throw "Signing metadata is missing: $metadataPath"
    }
    $metadata = Get-Content `
        -LiteralPath $metadataPath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json
    $metadata | Add-Member `
        -NotePropertyName AppDirectory `
        -NotePropertyValue $AppDirectory `
        -Force
    return $metadata
}

function Write-SigningMetadata {
    param(
        [Parameter(Mandatory = $true)]$Metadata,
        [Parameter(Mandatory = $true)][string]$AppDirectory
    )

    $record = [ordered]@{
        schemaVersion = $script:SchemaVersion
        appName = [string]$Metadata.appName
        packageId = [string]$Metadata.packageId
        repository = [string]$Metadata.repository
        secretPrefix = [string]$Metadata.secretPrefix
        alias = [string]$Metadata.alias
        keystoreFile = [string]$Metadata.keystoreFile
        certificateSha256 = [string]$Metadata.certificateSha256
        latestVersion = [string]$Metadata.latestVersion
        projectPath = [string]$Metadata.projectPath
        createdAtUtc = [string]$Metadata.createdAtUtc
        importedAtUtc = [string]$Metadata.importedAtUtc
        lastVerifiedAtUtc = [string]$Metadata.lastVerifiedAtUtc
    }
    $record |
        ConvertTo-Json |
        Set-Content `
            -LiteralPath (Get-MetadataPath -AppDirectory $AppDirectory) `
            -Encoding UTF8
}

function Get-KeytoolPath {
    [CmdletBinding()]
    param()

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidates.Add((Join-Path $env:JAVA_HOME "bin\keytool.exe"))
    }

    $keytoolCommand = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($null -ne $keytoolCommand) {
        $candidates.Add($keytoolCommand.Source)
    }

    foreach ($portableRoot in @(
        (Join-Path $PSScriptRoot "runtime\jdk"),
        (Join-Path $PSScriptRoot "runtime\java")
    )) {
        if (Test-Path -LiteralPath $portableRoot) {
            Get-ChildItem `
                -LiteralPath $portableRoot `
                -Filter keytool.exe `
                -Recurse `
                -ErrorAction SilentlyContinue |
                ForEach-Object { $candidates.Add($_.FullName) }
        }
    }

    $projectRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot "..\..")
    )
    $bundledJdk = Join-Path $projectRoot ".tools\jdk"
    if (Test-Path -LiteralPath $bundledJdk) {
        Get-ChildItem `
            -LiteralPath $bundledJdk `
            -Filter keytool.exe `
            -Recurse `
            -ErrorAction SilentlyContinue |
            ForEach-Object { $candidates.Add($_.FullName) }
    }

    $candidates.Add(
        "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
    )

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    throw (
        "Java keytool was not found. Install Java 17 or build Check in " +
        "once so the bundled JDK is available."
    )
}

function Get-GpgPath {
    [CmdletBinding()]
    param()

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($portablePath in @(
        (Join-Path $PSScriptRoot "runtime\gnupg\bin\gpg.exe"),
        (Join-Path $PSScriptRoot "runtime\git\usr\bin\gpg.exe")
    )) {
        $candidates.Add($portablePath)
    }

    $gpgCommand = Get-Command gpg.exe -ErrorAction SilentlyContinue
    if ($null -ne $gpgCommand) {
        $candidates.Add($gpgCommand.Source)
    }

    foreach ($installedPath in @(
        "C:\Program Files\Git\usr\bin\gpg.exe",
        "C:\Program Files\GnuPG\bin\gpg.exe",
        "C:\Program Files (x86)\GnuPG\bin\gpg.exe"
    )) {
        $candidates.Add($installedPath)
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    throw (
        "GnuPG was not found. Install Git for Windows or GnuPG, then " +
        "try the portable backup operation again."
    )
}

function ConvertTo-GpgFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $gpgPath = Get-GpgPath
    if ($gpgPath -match '\\Git\\usr\\bin\\gpg\.exe$') {
        if ($fullPath -match '^([A-Za-z]):\\(.*)$') {
            $drive = $Matches[1].ToLowerInvariant()
            $remainder = $Matches[2].Replace("\", "/")
            return "/$drive/$remainder"
        }
        if ($fullPath.StartsWith("\\")) {
            return "//" + $fullPath.Substring(2).Replace("\", "/")
        }
    }
    return $fullPath
}

function ConvertTo-NativeProcessArgument {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashCount = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append("\" * (($backslashCount * 2) + 1))
            [void]$builder.Append('"')
            $backslashCount = 0
            continue
        }
        if ($backslashCount -gt 0) {
            [void]$builder.Append("\" * $backslashCount)
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashCount -gt 0) {
        [void]$builder.Append("\" * ($backslashCount * 2))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Get-PortableTemporaryRoot {
    param()

    return Join-Path `
        ([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) `
        "AndroidSigningManager"
}

function New-PortableTemporaryDirectory {
    param()

    $temporaryRoot = Get-PortableTemporaryRoot
    New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
    $temporaryDirectory = Join-Path `
        $temporaryRoot `
        (".tmp-portable-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    return $temporaryDirectory
}

function Remove-PortableTemporaryDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$TemporaryDirectory
    )

    if (-not (Test-Path -LiteralPath $TemporaryDirectory)) {
        return
    }

    $allowedRoot = [IO.Path]::GetFullPath(
        (Get-PortableTemporaryRoot)
    ).TrimEnd("\")
    $resolvedDirectory = [IO.Path]::GetFullPath(
        $TemporaryDirectory
    ).TrimEnd("\")
    if (-not $resolvedDirectory.StartsWith(
        "$allowedRoot\",
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove a directory outside the portable staging root."
    }
    if (-not (Split-Path -Leaf $resolvedDirectory).StartsWith(
        ".tmp-portable-"
    )) {
        throw "Refusing to remove a non-portable temporary directory."
    }
    Remove-Item -LiteralPath $resolvedDirectory -Recurse -Force
}

function ConvertFrom-PortableSecureString {
    param(
        [Parameter(Mandatory = $true)][Security.SecureString]$SecureValue
    )

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $SecureValue
    )
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Assert-PortableBackupPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$MasterPassword
    )

    $plainText = ConvertFrom-PortableSecureString `
        -SecureValue $MasterPassword
    try {
        if ($plainText.Length -lt 12) {
            throw "The portable backup master password must be at least 12 characters."
        }
        if ($plainText -match '[\r\n]' -or $plainText -match '^\s+$') {
            throw "The portable backup master password cannot contain line breaks."
        }

        $categoryCount = 0
        if ($plainText -cmatch '[a-z]') {
            $categoryCount++
        }
        if ($plainText -cmatch '[A-Z]') {
            $categoryCount++
        }
        if ($plainText -match '\p{Nd}') {
            $categoryCount++
        }
        if ($plainText -match '[\p{P}\p{S}]') {
            $categoryCount++
        }
        if ($plainText -match '[^\x00-\x7F]' -and
            $plainText -match '\p{L}') {
            $categoryCount++
        }
        if ($categoryCount -lt 3) {
            throw (
                "Use at least three character groups: uppercase, " +
                "lowercase, numbers, symbols, or non-ASCII letters."
            )
        }
    } finally {
        $plainText = $null
    }
}

function Invoke-GpgWithPassphrase {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$MasterPassword
    )

    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.FileName = Get-GpgPath
    $processInfo.Arguments = (
        $Arguments |
            ForEach-Object {
                ConvertTo-NativeProcessArgument -Value ([string]$_)
            }
    ) -join " "
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $processInfo
    $plainText = $null
    $processStarted = $false
    try {
        if (-not $process.Start()) {
            throw "GnuPG could not be started."
        }
        $processStarted = $true
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        $plainText = ConvertFrom-PortableSecureString `
            -SecureValue $MasterPassword
        $process.StandardInput.WriteLine($plainText)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $standardOutput = $standardOutputTask.Result
        $standardError = $standardErrorTask.Result
        if ($process.ExitCode -ne 0) {
            $detail = $standardError.Trim()
            if ([string]::IsNullOrWhiteSpace($detail)) {
                $detail = $standardOutput.Trim()
            }
            if ([string]::IsNullOrWhiteSpace($detail)) {
                $detail = "Unknown GnuPG error."
            }
            throw "GnuPG failed: $detail"
        }
        return [PSCustomObject]@{
            StandardOutput = $standardOutput
            StandardError = $standardError
            ExitCode = $process.ExitCode
        }
    } finally {
        $plainText = $null
        if ($processStarted -and -not $process.HasExited) {
            try {
                $process.Kill()
            } catch {
            }
        }
        $process.Dispose()
    }
}

function New-RandomSigningPassword {
    [CmdletBinding()]
    param()

    $bytes = New-Object byte[] 32
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
        return (
            [BitConverter]::ToString($bytes)
        ).Replace("-", "").ToLowerInvariant()
    } finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
        $random.Dispose()
    }
}

function Invoke-Keytool {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$StorePassword,
        [string]$KeyPassword
    )

    $keytool = Get-KeytoolPath
    $previousStorePassword = $env:ASM_STORE_PASSWORD
    $previousKeyPassword = $env:ASM_KEY_PASSWORD
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        if ($PSBoundParameters.ContainsKey("StorePassword")) {
            $env:ASM_STORE_PASSWORD = $StorePassword
        }
        if ($PSBoundParameters.ContainsKey("KeyPassword")) {
            $env:ASM_KEY_PASSWORD = $KeyPassword
        }
        $ErrorActionPreference = "Continue"
        $output = & $keytool @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "keytool failed. Verify the certificate and password."
        }
        return @($output | ForEach-Object { $_.ToString() })
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($null -eq $previousStorePassword) {
            Remove-Item Env:ASM_STORE_PASSWORD -ErrorAction SilentlyContinue
        } else {
            $env:ASM_STORE_PASSWORD = $previousStorePassword
        }
        if ($null -eq $previousKeyPassword) {
            Remove-Item Env:ASM_KEY_PASSWORD -ErrorAction SilentlyContinue
        } else {
            $env:ASM_KEY_PASSWORD = $previousKeyPassword
        }
    }
}

function Get-CertificateFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeystorePath,
        [Parameter(Mandatory = $true)][string]$Alias,
        [Parameter(Mandatory = $true)][string]$StorePassword
    )

    $arguments = @(
        "-list",
        "-v",
        "-storetype", "PKCS12",
        "-keystore", $KeystorePath,
        "-storepass:env", "ASM_STORE_PASSWORD",
        "-alias", $Alias
    )
    $output = Invoke-Keytool `
        -Arguments $arguments `
        -StorePassword $StorePassword
    $joinedOutput = $output -join "`n"
    if ($joinedOutput -notmatch "SHA256:\s*([0-9A-Fa-f:]+)") {
        throw "keytool did not return a SHA-256 certificate fingerprint."
    }
    return $Matches[1].Replace(":", "").ToLowerInvariant()
}

function Save-SigningCredential {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$Alias,
        [Parameter(Mandatory = $true)][string]$StorePassword,
        [Parameter(Mandatory = $true)][string]$KeyPassword
    )

    $secret = @{
        storePassword = $StorePassword
        keyPassword = $KeyPassword
    } | ConvertTo-Json -Compress
    [AndroidSigningManager.NativeCredential]::Write(
        (Get-CredentialTarget -PackageId $PackageId),
        $Alias,
        $secret
    )
    $secret = $null
}

function Get-SigningCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageId
    )

    $secret = [AndroidSigningManager.NativeCredential]::Read(
        (Get-CredentialTarget -PackageId $PackageId)
    )
    if ([string]::IsNullOrWhiteSpace($secret)) {
        throw (
            "The password for $PackageId is not available in Windows " +
            "Credential Manager."
        )
    }
    try {
        $record = $secret | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($record.storePassword) -or
            [string]::IsNullOrWhiteSpace($record.keyPassword)) {
            throw "Stored signing credentials are incomplete."
        }
        return $record
    } finally {
        $secret = $null
    }
}

function Remove-TemporarySigningDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$VaultRoot,
        [Parameter(Mandatory = $true)][string]$TemporaryDirectory
    )

    if (-not (Test-Path -LiteralPath $TemporaryDirectory)) {
        return
    }
    $fullRoot = [IO.Path]::GetFullPath($VaultRoot).TrimEnd("\")
    $fullTemporary = [IO.Path]::GetFullPath(
        $TemporaryDirectory
    ).TrimEnd("\")
    $rootPrefix = "$fullRoot\"
    if (-not $fullTemporary.StartsWith(
        $rootPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove a directory outside the signing vault."
    }
    if (-not (Split-Path -Leaf $fullTemporary).StartsWith(".tmp-")) {
        throw "Refusing to remove a non-temporary signing directory."
    }
    Remove-Item -LiteralPath $fullTemporary -Recurse -Force
}

function New-SigningMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$AppName,
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$Repository,
        [Parameter(Mandatory = $true)][string]$SecretPrefix,
        [Parameter(Mandatory = $true)][string]$Alias,
        [Parameter(Mandatory = $true)][string]$Fingerprint,
        [string]$LatestVersion,
        [string]$ProjectPath,
        [bool]$Imported
    )

    $now = [DateTime]::UtcNow.ToString("o")
    return [PSCustomObject]@{
        schemaVersion = $script:SchemaVersion
        appName = $AppName
        packageId = $PackageId
        repository = $Repository
        secretPrefix = $SecretPrefix
        alias = $Alias
        keystoreFile = "release.p12"
        certificateSha256 = $Fingerprint
        latestVersion = $LatestVersion
        projectPath = $ProjectPath
        createdAtUtc = if ($Imported) { "" } else { $now }
        importedAtUtc = if ($Imported) { $now } else { "" }
        lastVerifiedAtUtc = $now
    }
}

function Assert-SigningInputs {
    param(
        [Parameter(Mandatory = $true)][string]$AppName,
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$Repository,
        [Parameter(Mandatory = $true)][string]$SecretPrefix,
        [Parameter(Mandatory = $true)][string]$Alias
    )

    if ([string]::IsNullOrWhiteSpace($AppName)) {
        throw "App name is required."
    }
    if (-not (Test-PackageId -PackageId $PackageId)) {
        throw "Invalid Android package id: $PackageId"
    }
    if (-not (Test-RepositoryName -Repository $Repository)) {
        throw "Repository must use owner/repository format."
    }
    if (-not (Test-SecretPrefix -SecretPrefix $SecretPrefix)) {
        throw "Secret prefix must contain uppercase letters, numbers, or underscores."
    }
    if ($Alias -notmatch "^[A-Za-z0-9_.-]+$") {
        throw "Key alias contains unsupported characters."
    }
}

function New-SigningApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AppName,
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$Repository = "",
        [Parameter(Mandatory = $true)][string]$SecretPrefix,
        [string]$Alias = "release",
        [string]$LatestVersion = "",
        [string]$ProjectPath = "",
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    Assert-SigningInputs `
        -AppName $AppName `
        -PackageId $PackageId `
        -Repository $Repository `
        -SecretPrefix $SecretPrefix `
        -Alias $Alias
    $fullRoot = Initialize-SigningVault -VaultRoot $VaultRoot
    $finalDirectory = Get-AppDirectory `
        -VaultRoot $fullRoot `
        -PackageId $PackageId
    if (Test-Path -LiteralPath $finalDirectory) {
        throw "A signing record already exists for $PackageId."
    }

    $temporaryDirectory = Join-Path `
        $fullRoot `
        (".tmp-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    $keystorePath = Join-Path $temporaryDirectory "release.p12"
    $password = New-RandomSigningPassword
    try {
        $distinguishedName = (
            "CN=" + $AppName.Replace(",", " ") +
            ", O=Android Signing Manager, C=CN"
        )
        $arguments = @(
            "-genkeypair",
            "-storetype", "PKCS12",
            "-keystore", $keystorePath,
            "-storepass:env", "ASM_STORE_PASSWORD",
            "-keypass:env", "ASM_KEY_PASSWORD",
            "-alias", $Alias,
            "-keyalg", "RSA",
            "-keysize", "2048",
            "-validity", "36500",
            "-dname", $distinguishedName
        )
        Invoke-Keytool `
            -Arguments $arguments `
            -StorePassword $password `
            -KeyPassword $password |
            Out-Null
        $fingerprint = Get-CertificateFingerprint `
            -KeystorePath $keystorePath `
            -Alias $Alias `
            -StorePassword $password
        Save-SigningCredential `
            -PackageId $PackageId `
            -Alias $Alias `
            -StorePassword $password `
            -KeyPassword $password
        $metadata = New-SigningMetadata `
            -AppName $AppName `
            -PackageId $PackageId `
            -Repository $Repository `
            -SecretPrefix $SecretPrefix `
            -Alias $Alias `
            -Fingerprint $fingerprint `
            -LatestVersion $LatestVersion `
            -ProjectPath $ProjectPath `
            -Imported $false
        Write-SigningMetadata `
            -Metadata $metadata `
            -AppDirectory $temporaryDirectory
        $fingerprint |
            Set-Content `
                -LiteralPath (
                    Join-Path $temporaryDirectory "certificate.sha256"
                ) `
                -Encoding ASCII
        Move-Item `
            -LiteralPath $temporaryDirectory `
            -Destination $finalDirectory
        return Read-SigningMetadata -AppDirectory $finalDirectory
    } catch {
        [AndroidSigningManager.NativeCredential]::Delete(
            (Get-CredentialTarget -PackageId $PackageId)
        ) | Out-Null
        Remove-TemporarySigningDirectory `
            -VaultRoot $fullRoot `
            -TemporaryDirectory $temporaryDirectory
        throw
    } finally {
        $password = $null
    }
}

function Import-SigningApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AppName,
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$Repository = "",
        [Parameter(Mandatory = $true)][string]$SecretPrefix,
        [Parameter(Mandatory = $true)][string]$Alias,
        [Parameter(Mandatory = $true)][string]$KeystorePath,
        [Parameter(Mandatory = $true)][string]$StorePassword,
        [string]$KeyPassword,
        [string]$LatestVersion = "",
        [string]$ProjectPath = "",
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    Assert-SigningInputs `
        -AppName $AppName `
        -PackageId $PackageId `
        -Repository $Repository `
        -SecretPrefix $SecretPrefix `
        -Alias $Alias
    if (-not (Test-Path -LiteralPath $KeystorePath)) {
        throw "Keystore file was not found: $KeystorePath"
    }
    if ([string]::IsNullOrWhiteSpace($KeyPassword)) {
        $KeyPassword = $StorePassword
    }

    $fullRoot = Initialize-SigningVault -VaultRoot $VaultRoot
    $finalDirectory = Get-AppDirectory `
        -VaultRoot $fullRoot `
        -PackageId $PackageId
    if (Test-Path -LiteralPath $finalDirectory) {
        throw "A signing record already exists for $PackageId."
    }

    $fingerprint = Get-CertificateFingerprint `
        -KeystorePath $KeystorePath `
        -Alias $Alias `
        -StorePassword $StorePassword
    $temporaryDirectory = Join-Path `
        $fullRoot `
        (".tmp-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    try {
        Copy-Item `
            -LiteralPath $KeystorePath `
            -Destination (
                Join-Path $temporaryDirectory "release.p12"
            )
        Save-SigningCredential `
            -PackageId $PackageId `
            -Alias $Alias `
            -StorePassword $StorePassword `
            -KeyPassword $KeyPassword
        $metadata = New-SigningMetadata `
            -AppName $AppName `
            -PackageId $PackageId `
            -Repository $Repository `
            -SecretPrefix $SecretPrefix `
            -Alias $Alias `
            -Fingerprint $fingerprint `
            -LatestVersion $LatestVersion `
            -ProjectPath $ProjectPath `
            -Imported $true
        Write-SigningMetadata `
            -Metadata $metadata `
            -AppDirectory $temporaryDirectory
        $fingerprint |
            Set-Content `
                -LiteralPath (
                    Join-Path $temporaryDirectory "certificate.sha256"
                ) `
                -Encoding ASCII
        Move-Item `
            -LiteralPath $temporaryDirectory `
            -Destination $finalDirectory
        return Read-SigningMetadata -AppDirectory $finalDirectory
    } catch {
        [AndroidSigningManager.NativeCredential]::Delete(
            (Get-CredentialTarget -PackageId $PackageId)
        ) | Out-Null
        Remove-TemporarySigningDirectory `
            -VaultRoot $fullRoot `
            -TemporaryDirectory $temporaryDirectory
        throw
    }
}

function Get-SigningApps {
    [CmdletBinding()]
    param(
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    $fullRoot = Initialize-SigningVault -VaultRoot $VaultRoot
    $records = @()
    Get-ChildItem `
        -LiteralPath $fullRoot `
        -Directory `
        -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.StartsWith(".tmp-") } |
        ForEach-Object {
            $metadataPath = Get-MetadataPath -AppDirectory $_.FullName
            if (Test-Path -LiteralPath $metadataPath) {
                $records += Read-SigningMetadata `
                    -AppDirectory $_.FullName
            }
        }
    return @($records | Sort-Object appName, packageId)
}

function Get-SigningApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    $directory = Get-AppDirectory `
        -VaultRoot (Initialize-SigningVault -VaultRoot $VaultRoot) `
        -PackageId $PackageId
    return Read-SigningMetadata -AppDirectory $directory
}

function Test-SigningApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    $metadata = Get-SigningApp `
        -PackageId $PackageId `
        -VaultRoot $VaultRoot
    $credential = Get-SigningCredential -PackageId $PackageId
    $keystorePath = Join-Path `
        $metadata.AppDirectory `
        $metadata.keystoreFile
    $fingerprint = Get-CertificateFingerprint `
        -KeystorePath $keystorePath `
        -Alias $metadata.alias `
        -StorePassword $credential.storePassword
    $matches = $fingerprint -eq $metadata.certificateSha256
    if ($matches) {
        $metadata.lastVerifiedAtUtc = [DateTime]::UtcNow.ToString("o")
        Write-SigningMetadata `
            -Metadata $metadata `
            -AppDirectory $metadata.AppDirectory
    }
    return [PSCustomObject]@{
        AppName = $metadata.appName
        PackageId = $metadata.packageId
        ExpectedFingerprint = $metadata.certificateSha256
        ActualFingerprint = $fingerprint
        Matches = $matches
        VerifiedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
}

function Update-SigningAppMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$AppName,
        [string]$Repository = "",
        [Parameter(Mandatory = $true)][string]$SecretPrefix,
        [string]$LatestVersion = "",
        [string]$ProjectPath = "",
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    $metadata = Get-SigningApp `
        -PackageId $PackageId `
        -VaultRoot $VaultRoot
    Assert-SigningInputs `
        -AppName $AppName `
        -PackageId $PackageId `
        -Repository $Repository `
        -SecretPrefix $SecretPrefix `
        -Alias $metadata.alias
    $metadata.appName = $AppName
    $metadata.repository = $Repository
    $metadata.secretPrefix = $SecretPrefix
    $metadata.latestVersion = $LatestVersion
    $metadata.projectPath = $ProjectPath
    Write-SigningMetadata `
        -Metadata $metadata `
        -AppDirectory $metadata.AppDirectory
    return Get-SigningApp `
        -PackageId $PackageId `
        -VaultRoot $VaultRoot
}

function Get-GitHubSecretEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    $metadata = Get-SigningApp `
        -PackageId $PackageId `
        -VaultRoot $VaultRoot
    $credential = Get-SigningCredential -PackageId $PackageId
    $keystorePath = Join-Path `
        $metadata.AppDirectory `
        $metadata.keystoreFile
    $base64 = [Convert]::ToBase64String(
        [IO.File]::ReadAllBytes($keystorePath)
    )
    $prefix = $metadata.secretPrefix
    return @(
        [PSCustomObject]@{
            Name = "${prefix}_KEYSTORE_BASE64"
            Value = $base64
        },
        [PSCustomObject]@{
            Name = "${prefix}_KEYSTORE_PASSWORD"
            Value = $credential.storePassword
        },
        [PSCustomObject]@{
            Name = "${prefix}_KEY_ALIAS"
            Value = $metadata.alias
        },
        [PSCustomObject]@{
            Name = "${prefix}_KEY_PASSWORD"
            Value = $credential.keyPassword
        }
    )
}

function Get-SigningRecoveryRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    $metadata = Get-SigningApp `
        -PackageId $PackageId `
        -VaultRoot $VaultRoot
    $credential = Get-SigningCredential -PackageId $PackageId
    return @"
App name: $($metadata.appName)
Package id: $($metadata.packageId)
Repository: $($metadata.repository)
Certificate alias: $($metadata.alias)
Certificate SHA-256: $($metadata.certificateSha256)
Keystore password: $($credential.storePassword)
Key password: $($credential.keyPassword)
Vault file: $(
    Join-Path $metadata.AppDirectory $metadata.keystoreFile
)
"@
}

function Get-ByteArraySha256 {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return (
            [BitConverter]::ToString(
                $algorithm.ComputeHash($Bytes)
            )
        ).Replace("-", "").ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-StreamSha256 {
    param(
        [Parameter(Mandatory = $true)][IO.Stream]$Stream
    )

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return (
            [BitConverter]::ToString(
                $algorithm.ComputeHash($Stream)
            )
        ).Replace("-", "").ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Add-PortableZipFile {
    param(
        [Parameter(Mandatory = $true)]
        [IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    $source = Get-Item -LiteralPath $SourcePath
    $entry = $Archive.CreateEntry(
        $EntryName,
        [IO.Compression.CompressionLevel]::Optimal
    )
    $sourceStream = [IO.File]::OpenRead($source.FullName)
    $entryStream = $entry.Open()
    try {
        $sourceStream.CopyTo($entryStream)
    } finally {
        $entryStream.Dispose()
        $sourceStream.Dispose()
    }
    return [PSCustomObject]@{
        path = $EntryName
        length = [long]$source.Length
        sha256 = (
            Get-FileHash `
                -Algorithm SHA256 `
                -LiteralPath $source.FullName
        ).Hash.ToLowerInvariant()
    }
}

function Add-PortableZipText {
    param(
        [Parameter(Mandatory = $true)]
        [IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$EntryName,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $encoding = New-Object Text.UTF8Encoding($false)
    $bytes = $encoding.GetBytes($Text)
    $entry = $Archive.CreateEntry(
        $EntryName,
        [IO.Compression.CompressionLevel]::Optimal
    )
    $entryStream = $entry.Open()
    try {
        $entryStream.Write($bytes, 0, $bytes.Length)
    } finally {
        $entryStream.Dispose()
    }
    return [PSCustomObject]@{
        path = $EntryName
        length = [long]$bytes.Length
        sha256 = Get-ByteArraySha256 -Bytes $bytes
    }
}

function Read-PortableZipText {
    param(
        [Parameter(Mandatory = $true)]
        [IO.Compression.ZipArchiveEntry]$Entry
    )

    $stream = $Entry.Open()
    $reader = New-Object IO.StreamReader(
        $stream,
        (New-Object Text.UTF8Encoding($false, $true)),
        $true
    )
    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Copy-PortableZipEntry {
    param(
        [Parameter(Mandatory = $true)]
        [IO.Compression.ZipArchiveEntry]$Entry,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $parent = Split-Path -Parent $DestinationPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $sourceStream = $Entry.Open()
    $destinationStream = New-Object IO.FileStream(
        $DestinationPath,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try {
        $sourceStream.CopyTo($destinationStream)
    } finally {
        $destinationStream.Dispose()
        $sourceStream.Dispose()
    }
}

function New-PortableVaultArchive {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$VaultRoot
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $apps = @(Get-SigningApps -VaultRoot $VaultRoot)
    if ($apps.Count -eq 0) {
        throw "The signing vault is empty. There is nothing to back up."
    }

    $archiveStream = New-Object IO.FileStream(
        $ArchivePath,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
    $archive = New-Object IO.Compression.ZipArchive(
        $archiveStream,
        [IO.Compression.ZipArchiveMode]::Create,
        $false
    )
    $credentialRecords = New-Object System.Collections.ArrayList
    $fileRecords = New-Object System.Collections.ArrayList
    $appRecords = New-Object System.Collections.ArrayList
    try {
        foreach ($listedApp in $apps) {
            $verification = Test-SigningApp `
                -PackageId $listedApp.packageId `
                -VaultRoot $VaultRoot
            if (-not $verification.Matches) {
                throw (
                    "Certificate verification failed before backup: " +
                    $listedApp.packageId
                )
            }

            $app = Get-SigningApp `
                -PackageId $listedApp.packageId `
                -VaultRoot $VaultRoot
            $credential = Get-SigningCredential `
                -PackageId $app.packageId
            $entryRoot = "apps/$($app.packageId)"
            $metadataPath = Get-MetadataPath `
                -AppDirectory $app.AppDirectory
            $keystorePath = Join-Path `
                $app.AppDirectory `
                $app.keystoreFile
            $fingerprintPath = Join-Path `
                $app.AppDirectory `
                "certificate.sha256"

            foreach ($fileDefinition in @(
                @{
                    Source = $metadataPath
                    Entry = "$entryRoot/metadata.json"
                },
                @{
                    Source = $keystorePath
                    Entry = "$entryRoot/$($app.keystoreFile)"
                },
                @{
                    Source = $fingerprintPath
                    Entry = "$entryRoot/certificate.sha256"
                }
            )) {
                $fileRecords.Add(
                    (Add-PortableZipFile `
                        -Archive $archive `
                        -SourcePath $fileDefinition.Source `
                        -EntryName $fileDefinition.Entry)
                ) | Out-Null
            }

            $credentialRecords.Add([PSCustomObject]@{
                packageId = [string]$app.packageId
                alias = [string]$app.alias
                storePassword = [string]$credential.storePassword
                keyPassword = [string]$credential.keyPassword
            }) | Out-Null
            $appRecords.Add([PSCustomObject]@{
                appName = [string]$app.appName
                packageId = [string]$app.packageId
                alias = [string]$app.alias
                keystoreFile = [string]$app.keystoreFile
                certificateSha256 = [string]$app.certificateSha256
            }) | Out-Null
            $credential = $null
        }

        $credentialsDocument = [ordered]@{
            schemaVersion = $script:PortableVaultSchemaVersion
            credentials = @($credentialRecords)
        } | ConvertTo-Json -Depth 6
        $fileRecords.Add(
            (Add-PortableZipText `
                -Archive $archive `
                -EntryName "credentials.json" `
                -Text $credentialsDocument)
        ) | Out-Null

        $manifest = [ordered]@{
            format = $script:PortableVaultFormat
            schemaVersion = $script:PortableVaultSchemaVersion
            createdAtUtc = [DateTime]::UtcNow.ToString("o")
            appCount = $appRecords.Count
            apps = @($appRecords)
            files = @($fileRecords | Sort-Object path)
        }
        $manifestText = $manifest | ConvertTo-Json -Depth 8
        Add-PortableZipText `
            -Archive $archive `
            -EntryName "vault-manifest.json" `
            -Text $manifestText |
            Out-Null
        return [PSCustomObject]$manifest
    } finally {
        foreach ($record in $credentialRecords) {
            $record.storePassword = $null
            $record.keyPassword = $null
        }
        $credentialsDocument = $null
        $credentialRecords = $null
        $archive.Dispose()
        $archiveStream.Dispose()
    }
}

function Test-PortableArchivePath {
    param(
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    if ([string]::IsNullOrWhiteSpace($EntryName) -or
        $EntryName.StartsWith("/") -or
        $EntryName.Contains("\") -or
        $EntryName.Contains(":")) {
        return $false
    }
    foreach ($segment in $EntryName.Split("/")) {
        if ([string]::IsNullOrWhiteSpace($segment) -or
            $segment -in @(".", "..")) {
            return $false
        }
    }
    return $true
}

function Test-PortableVaultArchive {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entryMap = @{}
        foreach ($entry in $archive.Entries) {
            if (-not (Test-PortableArchivePath -EntryName $entry.FullName)) {
                throw "The portable backup contains an unsafe archive path."
            }
            if ($entryMap.ContainsKey($entry.FullName)) {
                throw "The portable backup contains duplicate archive entries."
            }
            $entryMap[$entry.FullName] = $entry
        }

        if (-not $entryMap.ContainsKey("vault-manifest.json") -or
            -not $entryMap.ContainsKey("credentials.json")) {
            throw "The portable backup manifest or credential record is missing."
        }

        $manifest = (
            Read-PortableZipText `
                -Entry $entryMap["vault-manifest.json"]
        ) | ConvertFrom-Json
        if ($manifest.format -ne $script:PortableVaultFormat -or
            [int]$manifest.schemaVersion -ne
                $script:PortableVaultSchemaVersion) {
            throw "The portable backup format is not supported."
        }

        $expectedEntries = @{
            "vault-manifest.json" = $true
        }
        foreach ($fileRecord in @($manifest.files)) {
            $entryName = [string]$fileRecord.path
            if (-not (Test-PortableArchivePath -EntryName $entryName) -or
                -not $entryMap.ContainsKey($entryName)) {
                throw "A portable backup file is missing: $entryName"
            }
            if ($expectedEntries.ContainsKey($entryName)) {
                throw "The portable backup manifest contains duplicate files."
            }
            $expectedEntries[$entryName] = $true
            $entry = $entryMap[$entryName]
            if ([long]$entry.Length -ne [long]$fileRecord.length) {
                throw "Portable backup file length mismatch: $entryName"
            }
            $entryStream = $entry.Open()
            try {
                $actualHash = Get-StreamSha256 -Stream $entryStream
            } finally {
                $entryStream.Dispose()
            }
            if ($actualHash -ne [string]$fileRecord.sha256) {
                throw "Portable backup SHA-256 mismatch: $entryName"
            }
        }
        foreach ($entryName in $entryMap.Keys) {
            if (-not $expectedEntries.ContainsKey($entryName)) {
                throw "The portable backup contains an unlisted file: $entryName"
            }
        }

        $credentialsDocument = (
            Read-PortableZipText `
                -Entry $entryMap["credentials.json"]
        ) | ConvertFrom-Json
        if ([int]$credentialsDocument.schemaVersion -ne
            $script:PortableVaultSchemaVersion) {
            throw "The portable credential record format is not supported."
        }

        $credentialMap = @{}
        foreach ($credential in @($credentialsDocument.credentials)) {
            $packageId = [string]$credential.packageId
            if (-not (Test-PackageId -PackageId $packageId) -or
                $credentialMap.ContainsKey($packageId) -or
                [string]::IsNullOrWhiteSpace($credential.alias) -or
                [string]::IsNullOrWhiteSpace(
                    $credential.storePassword
                ) -or
                [string]::IsNullOrWhiteSpace(
                    $credential.keyPassword
                )) {
                throw "The portable credential record is invalid."
            }
            $credentialMap[$packageId] = $credential
        }

        $validatedApps = New-Object System.Collections.ArrayList
        $seenPackages = @{}
        foreach ($appRecord in @($manifest.apps)) {
            $packageId = [string]$appRecord.packageId
            if (-not (Test-PackageId -PackageId $packageId) -or
                $seenPackages.ContainsKey($packageId) -or
                -not $credentialMap.ContainsKey($packageId)) {
                throw "The portable app manifest is invalid."
            }
            $seenPackages[$packageId] = $true
            $metadataEntryName = "apps/$packageId/metadata.json"
            if (-not $entryMap.ContainsKey($metadataEntryName)) {
                throw "Signing metadata is missing for $packageId."
            }
            $metadata = (
                Read-PortableZipText `
                    -Entry $entryMap[$metadataEntryName]
            ) | ConvertFrom-Json
            if ([string]$metadata.packageId -ne $packageId -or
                [string]$metadata.alias -ne [string]$appRecord.alias -or
                [string]$metadata.keystoreFile -ne
                    [string]$appRecord.keystoreFile -or
                [string]$metadata.certificateSha256 -ne
                    [string]$appRecord.certificateSha256 -or
                [string]$credentialMap[$packageId].alias -ne
                    [string]$appRecord.alias) {
                throw "Portable signing metadata mismatch for $packageId."
            }
            foreach ($requiredEntry in @(
                $metadataEntryName,
                "apps/$packageId/$($metadata.keystoreFile)",
                "apps/$packageId/certificate.sha256"
            )) {
                if (-not $entryMap.ContainsKey($requiredEntry)) {
                    throw "A signing file is missing for $packageId."
                }
            }
            $validatedApps.Add([PSCustomObject]@{
                App = $appRecord
                Metadata = $metadata
                Credential = $credentialMap[$packageId]
            }) | Out-Null
        }
        if ($validatedApps.Count -ne [int]$manifest.appCount -or
            $credentialMap.Count -ne $validatedApps.Count) {
            throw "The portable backup app count is inconsistent."
        }

        return [PSCustomObject]@{
            Manifest = $manifest
            Apps = @($validatedApps)
            EntryNames = @($entryMap.Keys)
        }
    } finally {
        $archive.Dispose()
    }
}

function Invoke-PortableVaultEncryption {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$GpgHome,
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$MasterPassword
    )

    New-Item -ItemType Directory -Force -Path $GpgHome | Out-Null
    $gpgHomePath = ConvertTo-GpgFilePath -Path $GpgHome
    $gpgInputPath = ConvertTo-GpgFilePath -Path $InputPath
    $gpgOutputPath = ConvertTo-GpgFilePath -Path $OutputPath
    Invoke-GpgWithPassphrase `
        -MasterPassword $MasterPassword `
        -Arguments @(
            "--no-options",
            "--homedir", $gpgHomePath,
            "--batch",
            "--yes",
            "--no-tty",
            "--pinentry-mode", "loopback",
            "--no-symkey-cache",
            "--passphrase-fd", "0",
            "--cipher-algo", "AES256",
            "--s2k-mode", "3",
            "--s2k-digest-algo", "SHA512",
            "--s2k-count", "65011712",
            "--compress-algo", "none",
            "--output", $gpgOutputPath,
            "--symmetric", $gpgInputPath
        ) |
        Out-Null
}

function Invoke-PortableVaultDecryption {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$GpgHome,
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$MasterPassword
    )

    New-Item -ItemType Directory -Force -Path $GpgHome | Out-Null
    $gpgHomePath = ConvertTo-GpgFilePath -Path $GpgHome
    $gpgInputPath = ConvertTo-GpgFilePath -Path $InputPath
    $gpgOutputPath = ConvertTo-GpgFilePath -Path $OutputPath
    Invoke-GpgWithPassphrase `
        -MasterPassword $MasterPassword `
        -Arguments @(
            "--no-options",
            "--homedir", $gpgHomePath,
            "--batch",
            "--yes",
            "--no-tty",
            "--pinentry-mode", "loopback",
            "--no-symkey-cache",
            "--passphrase-fd", "0",
            "--output", $gpgOutputPath,
            "--decrypt", $gpgInputPath
        ) |
        Out-Null
}

function Export-PortableSigningVault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$MasterPassword,
        [string]$FileName = "",
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    Assert-PortableBackupPassword -MasterPassword $MasterPassword
    $fullDestinationRoot = Resolve-PortableDestinationPath `
        -Path $DestinationRoot
    New-Item -ItemType Directory -Force -Path $fullDestinationRoot |
        Out-Null
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        $timestamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
        $FileName = "Android-Signing-Vault-$timestamp" +
            $script:PortableBackupExtension
    }
    if (-not $FileName.EndsWith(
        $script:PortableBackupExtension,
        [StringComparison]::OrdinalIgnoreCase
    ) -or $FileName -ne (Split-Path -Leaf $FileName)) {
        throw "The portable backup file name is invalid."
    }

    $finalPath = Join-Path $fullDestinationRoot $FileName
    if (Test-Path -LiteralPath $finalPath) {
        throw "A portable backup already exists: $finalPath"
    }
    $partialPath = Join-Path `
        $fullDestinationRoot `
        (".partial-" + [Guid]::NewGuid().ToString("N") + ".gpg")
    $temporaryDirectory = New-PortableTemporaryDirectory
    $archivePath = Join-Path $temporaryDirectory "vault.zip"
    $verificationArchivePath = Join-Path `
        $temporaryDirectory `
        "verification.zip"
    $encryptHome = Join-Path $temporaryDirectory "gpg-encrypt"
    $verifyHome = Join-Path $temporaryDirectory "gpg-verify"
    try {
        $manifest = New-PortableVaultArchive `
            -ArchivePath $archivePath `
            -VaultRoot $VaultRoot
        Invoke-PortableVaultEncryption `
            -InputPath $archivePath `
            -OutputPath $partialPath `
            -GpgHome $encryptHome `
            -MasterPassword $MasterPassword
        Invoke-PortableVaultDecryption `
            -InputPath $partialPath `
            -OutputPath $verificationArchivePath `
            -GpgHome $verifyHome `
            -MasterPassword $MasterPassword
        $verification = Test-PortableVaultArchive `
            -ArchivePath $verificationArchivePath
        if ([int]$verification.Manifest.appCount -ne
            [int]$manifest.appCount) {
            throw "Portable backup self-verification app count mismatch."
        }

        Move-Item -LiteralPath $partialPath -Destination $finalPath
        return [PSCustomObject]@{
            BackupPath = $finalPath
            AppCount = [int]$manifest.appCount
            CreatedAtUtc = [string]$manifest.createdAtUtc
            Sha256 = (
                Get-FileHash `
                    -Algorithm SHA256 `
                    -LiteralPath $finalPath
            ).Hash.ToLowerInvariant()
        }
    } finally {
        if (Test-Path -LiteralPath $partialPath) {
            Remove-Item -LiteralPath $partialPath -Force
        }
        Remove-PortableTemporaryDirectory `
            -TemporaryDirectory $temporaryDirectory
    }
}

function Test-PortableSigningVaultBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$MasterPassword
    )

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        throw "The portable backup file was not found: $BackupPath"
    }
    $temporaryDirectory = New-PortableTemporaryDirectory
    $archivePath = Join-Path $temporaryDirectory "vault.zip"
    $gpgHome = Join-Path $temporaryDirectory "gpg-verify"
    try {
        Invoke-PortableVaultDecryption `
            -InputPath ([IO.Path]::GetFullPath($BackupPath)) `
            -OutputPath $archivePath `
            -GpgHome $gpgHome `
            -MasterPassword $MasterPassword
        $verification = Test-PortableVaultArchive `
            -ArchivePath $archivePath
        return [PSCustomObject]@{
            BackupPath = [IO.Path]::GetFullPath($BackupPath)
            AppCount = [int]$verification.Manifest.appCount
            CreatedAtUtc = [string]$verification.Manifest.createdAtUtc
            Valid = $true
        }
    } finally {
        Remove-PortableTemporaryDirectory `
            -TemporaryDirectory $temporaryDirectory
    }
}

function Import-PortableSigningVault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$MasterPassword,
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        throw "The portable backup file was not found: $BackupPath"
    }

    $fullVaultRoot = Initialize-SigningVault -VaultRoot $VaultRoot
    $temporaryDirectory = New-PortableTemporaryDirectory
    $archivePath = Join-Path $temporaryDirectory "vault.zip"
    $gpgHome = Join-Path $temporaryDirectory "gpg-restore"
    $restoreDirectory = Join-Path `
        $fullVaultRoot `
        (".tmp-restore-" + [Guid]::NewGuid().ToString("N"))
    $operations = New-Object System.Collections.ArrayList
    $savedCredentials = New-Object System.Collections.ArrayList
    $movedDirectories = New-Object System.Collections.ArrayList
    $completed = $false
    try {
        Invoke-PortableVaultDecryption `
            -InputPath ([IO.Path]::GetFullPath($BackupPath)) `
            -OutputPath $archivePath `
            -GpgHome $gpgHome `
            -MasterPassword $MasterPassword
        $verification = Test-PortableVaultArchive `
            -ArchivePath $archivePath

        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            $entryMap = @{}
            foreach ($entry in $archive.Entries) {
                $entryMap[$entry.FullName] = $entry
            }
            New-Item -ItemType Directory -Path $restoreDirectory |
                Out-Null

            foreach ($validatedApp in @($verification.Apps)) {
                $appRecord = $validatedApp.App
                $metadata = $validatedApp.Metadata
                $credential = $validatedApp.Credential
                $packageId = [string]$appRecord.packageId
                $finalDirectory = Get-AppDirectory `
                    -VaultRoot $fullVaultRoot `
                    -PackageId $packageId
                $isNew = -not (Test-Path -LiteralPath $finalDirectory)
                if ($isNew) {
                    $workingDirectory = Join-Path `
                        $restoreDirectory `
                        $packageId
                    New-Item `
                        -ItemType Directory `
                        -Path $workingDirectory |
                        Out-Null
                    foreach ($fileName in @(
                        "metadata.json",
                        [string]$metadata.keystoreFile,
                        "certificate.sha256"
                    )) {
                        Copy-PortableZipEntry `
                            -Entry $entryMap[
                                "apps/$packageId/$fileName"
                            ] `
                            -DestinationPath (
                                Join-Path $workingDirectory $fileName
                            )
                    }
                } else {
                    $workingDirectory = $finalDirectory
                    $existing = Read-SigningMetadata `
                        -AppDirectory $finalDirectory
                    if ([string]$existing.certificateSha256 -ne
                        [string]$metadata.certificateSha256 -or
                        [string]$existing.alias -ne
                        [string]$metadata.alias) {
                        throw (
                            "A different signing record already exists for " +
                            "$packageId."
                        )
                    }
                }

                $keystorePath = Join-Path `
                    $workingDirectory `
                    $metadata.keystoreFile
                $actualFingerprint = Get-CertificateFingerprint `
                    -KeystorePath $keystorePath `
                    -Alias $metadata.alias `
                    -StorePassword $credential.storePassword
                if ($actualFingerprint -ne
                    [string]$metadata.certificateSha256) {
                    throw (
                        "Portable certificate verification failed for " +
                        "$packageId."
                    )
                }
                $operations.Add([PSCustomObject]@{
                    PackageId = $packageId
                    Alias = [string]$metadata.alias
                    Credential = $credential
                    IsNew = $isNew
                    WorkingDirectory = $workingDirectory
                    FinalDirectory = $finalDirectory
                }) | Out-Null
            }
        } finally {
            $archive.Dispose()
        }

        foreach ($operation in $operations) {
            $target = Get-CredentialTarget `
                -PackageId $operation.PackageId
            $previousSecret = [AndroidSigningManager.NativeCredential]::Read(
                $target
            )
            $savedCredentials.Add([PSCustomObject]@{
                Target = $target
                Alias = $operation.Alias
                PreviousSecret = $previousSecret
            }) | Out-Null
            Save-SigningCredential `
                -PackageId $operation.PackageId `
                -Alias $operation.Alias `
                -StorePassword $operation.Credential.storePassword `
                -KeyPassword $operation.Credential.keyPassword
        }

        foreach ($operation in $operations) {
            if ($operation.IsNew) {
                Move-Item `
                    -LiteralPath $operation.WorkingDirectory `
                    -Destination $operation.FinalDirectory
                $movedDirectories.Add($operation) | Out-Null
            }
        }

        foreach ($operation in $operations) {
            $result = Test-SigningApp `
                -PackageId $operation.PackageId `
                -VaultRoot $fullVaultRoot
            if (-not $result.Matches) {
                throw (
                    "Restored signing verification failed for " +
                    $operation.PackageId
                )
            }
        }

        $completed = $true
        return [PSCustomObject]@{
            BackupPath = [IO.Path]::GetFullPath($BackupPath)
            RestoredApps = @(
                $operations |
                    Where-Object { $_.IsNew }
            ).Count
            ExistingApps = @(
                $operations |
                    Where-Object { -not $_.IsNew }
            ).Count
            CredentialCount = $operations.Count
            CreatedAtUtc = [string]$verification.Manifest.createdAtUtc
        }
    } finally {
        if (-not $completed) {
            foreach ($operation in @($movedDirectories) |
                Sort-Object PackageId -Descending) {
                if (Test-Path -LiteralPath $operation.FinalDirectory) {
                    Move-Item `
                        -LiteralPath $operation.FinalDirectory `
                        -Destination $operation.WorkingDirectory `
                        -ErrorAction SilentlyContinue
                }
            }
            foreach ($savedCredential in $savedCredentials) {
                if ($null -eq $savedCredential.PreviousSecret) {
                    [AndroidSigningManager.NativeCredential]::Delete(
                        $savedCredential.Target
                    ) | Out-Null
                } else {
                    [AndroidSigningManager.NativeCredential]::Write(
                        $savedCredential.Target,
                        $savedCredential.Alias,
                        $savedCredential.PreviousSecret
                    )
                }
            }
        }
        foreach ($operation in $operations) {
            if ($null -ne $operation.Credential) {
                $operation.Credential.storePassword = $null
                $operation.Credential.keyPassword = $null
            }
        }
        foreach ($savedCredential in $savedCredentials) {
            $savedCredential.PreviousSecret = $null
        }
        if (Test-Path -LiteralPath $restoreDirectory) {
            Remove-TemporarySigningDirectory `
                -VaultRoot $fullVaultRoot `
                -TemporaryDirectory $restoreDirectory
        }
        Remove-PortableTemporaryDirectory `
            -TemporaryDirectory $temporaryDirectory
    }
}

function Remove-PortableBundleStaging {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$StagingDirectory
    )

    if (-not (Test-Path -LiteralPath $StagingDirectory)) {
        return
    }
    $fullRoot = [IO.Path]::GetFullPath(
        $DestinationRoot
    ).TrimEnd("\")
    $fullStaging = [IO.Path]::GetFullPath(
        $StagingDirectory
    ).TrimEnd("\")
    if (-not $fullStaging.StartsWith(
        "$fullRoot\",
        [StringComparison]::OrdinalIgnoreCase
    ) -or -not (Split-Path -Leaf $fullStaging).StartsWith(
        ".tmp-android-signing-manager-"
    )) {
        throw "Refusing to remove an invalid portable bundle staging directory."
    }
    Remove-Item -LiteralPath $fullStaging -Recurse -Force
}

function Export-PortableSigningManagerBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$MasterPassword,
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    Assert-PortableBackupPassword -MasterPassword $MasterPassword
    $fullDestinationRoot = Resolve-PortableDestinationPath `
        -Path $DestinationRoot
    New-Item -ItemType Directory -Force -Path $fullDestinationRoot |
        Out-Null
    $timestamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
    $bundleName = "Android-Signing-Manager-Portable-$timestamp"
    $bundlePath = Join-Path $fullDestinationRoot $bundleName
    if (Test-Path -LiteralPath $bundlePath) {
        $bundleName += "-" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
        $bundlePath = Join-Path $fullDestinationRoot $bundleName
    }
    $stagingDirectory = Join-Path `
        $fullDestinationRoot `
        (".tmp-android-signing-manager-" +
            [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
    try {
        foreach ($fileName in @(
            "SigningVault.psm1",
            "AndroidSigningManager.ps1",
            "Start-AndroidSigningManager.cmd",
            "strings.zh-CN.json",
            "README.md"
        )) {
            $sourcePath = Join-Path $PSScriptRoot $fileName
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                throw "Portable manager file is missing: $fileName"
            }
            Copy-Item `
                -LiteralPath $sourcePath `
                -Destination (Join-Path $stagingDirectory $fileName)
        }
        $runtimeSource = Join-Path $PSScriptRoot "runtime"
        if (Test-Path -LiteralPath $runtimeSource -PathType Container) {
            Copy-Item `
                -LiteralPath $runtimeSource `
                -Destination (Join-Path $stagingDirectory "runtime") `
                -Recurse
        }

        $backup = Export-PortableSigningVault `
            -DestinationRoot $stagingDirectory `
            -MasterPassword $MasterPassword `
            -FileName ("vault-backup" + $script:PortableBackupExtension) `
            -VaultRoot $VaultRoot
        $checksumLines = Get-ChildItem `
            -LiteralPath $stagingDirectory `
            -File `
            -Recurse |
            Sort-Object FullName |
            ForEach-Object {
                $hash = (
                    Get-FileHash `
                        -Algorithm SHA256 `
                        -LiteralPath $_.FullName
                ).Hash.ToLowerInvariant()
                $relativePath = $_.FullName.Substring(
                    $stagingDirectory.Length
                ).TrimStart("\").Replace("\", "/")
                "$hash  $relativePath"
            }
        $checksumLines |
            Set-Content `
                -LiteralPath (
                    Join-Path $stagingDirectory "CHECKSUMS.sha256"
                ) `
                -Encoding ASCII

        Move-Item `
            -LiteralPath $stagingDirectory `
            -Destination $bundlePath
        return [PSCustomObject]@{
            BundlePath = $bundlePath
            BackupPath = Join-Path `
                $bundlePath `
                (Split-Path -Leaf $backup.BackupPath)
            AppCount = $backup.AppCount
            BackupSha256 = $backup.Sha256
        }
    } finally {
        if (Test-Path -LiteralPath $stagingDirectory) {
            Remove-PortableBundleStaging `
                -DestinationRoot $fullDestinationRoot `
                -StagingDirectory $stagingDirectory
        }
    }
}

function Export-SigningAppBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    $metadata = Get-SigningApp `
        -PackageId $PackageId `
        -VaultRoot $VaultRoot
    $timestamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
    $backupDirectory = Join-Path `
        ([IO.Path]::GetFullPath($DestinationRoot)) `
        "$PackageId-$timestamp"
    New-Item -ItemType Directory -Force -Path $backupDirectory |
        Out-Null
    Copy-Item `
        -LiteralPath (
            Join-Path $metadata.AppDirectory $metadata.keystoreFile
        ) `
        -Destination (
            Join-Path $backupDirectory $metadata.keystoreFile
        )
    Copy-Item `
        -LiteralPath (
            Get-MetadataPath -AppDirectory $metadata.AppDirectory
        ) `
        -Destination (
            Join-Path $backupDirectory "metadata.json"
        )
    Copy-Item `
        -LiteralPath (
            Join-Path $metadata.AppDirectory "certificate.sha256"
        ) `
        -Destination (
            Join-Path $backupDirectory "certificate.sha256"
        )

    @"
This backup contains the password-protected signing certificate and metadata.
It does not contain the password stored in Windows Credential Manager.
Store the recovery record in a separate password manager.
"@ |
        Set-Content `
            -LiteralPath (
                Join-Path $backupDirectory "RECOVERY-README.txt"
            ) `
            -Encoding UTF8

    $manifestLines = Get-ChildItem `
        -LiteralPath $backupDirectory `
        -File |
        Where-Object { $_.Name -ne "manifest.sha256" } |
        Sort-Object Name |
        ForEach-Object {
            $hash = (
                Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName
            ).Hash.ToLowerInvariant()
            "$hash  $($_.Name)"
        }
    $manifestLines |
        Set-Content `
            -LiteralPath (
                Join-Path $backupDirectory "manifest.sha256"
            ) `
            -Encoding ASCII
    return $backupDirectory
}

function Import-CheckInSigning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string]$VaultRoot = (Get-DefaultSigningVaultRoot)
    )

    $fullProjectPath = [IO.Path]::GetFullPath($ProjectPath)
    $propertiesPath = Join-Path `
        $fullProjectPath `
        ".signing\clockin-release.properties"
    $keystorePath = Join-Path `
        $fullProjectPath `
        ".signing\clockin-release.p12"
    $buildFile = Join-Path $fullProjectPath "app\build.gradle"
    if (-not (Test-Path -LiteralPath $propertiesPath) -or
        -not (Test-Path -LiteralPath $keystorePath)) {
        throw "Check in signing files were not found."
    }
    $properties = ConvertFrom-StringData (
        Get-Content `
            -LiteralPath $propertiesPath `
            -Raw `
            -Encoding UTF8
    )
    if ([string]::IsNullOrWhiteSpace($properties.keyAlias) -or
        [string]::IsNullOrWhiteSpace($properties.keystorePassword)) {
        throw "Check in signing properties are incomplete."
    }
    $version = ""
    if (Test-Path -LiteralPath $buildFile) {
        $buildText = Get-Content -LiteralPath $buildFile -Raw
        if ($buildText -match 'versionName\s+"([^"]+)"') {
            $version = $Matches[1]
        }
    }

    $existingDirectory = Get-AppDirectory `
        -VaultRoot (Initialize-SigningVault -VaultRoot $VaultRoot) `
        -PackageId "com.clockin.assistant"
    if (Test-Path -LiteralPath $existingDirectory) {
        return Get-SigningApp `
            -PackageId "com.clockin.assistant" `
            -VaultRoot $VaultRoot
    }

    return Import-SigningApp `
        -AppName "Check in" `
        -PackageId "com.clockin.assistant" `
        -Repository "1510952971/check-in" `
        -SecretPrefix "CLOCKIN" `
        -Alias $properties.keyAlias `
        -KeystorePath $keystorePath `
        -StorePassword $properties.keystorePassword `
        -KeyPassword $properties.keystorePassword `
        -LatestVersion $version `
        -ProjectPath $fullProjectPath `
        -VaultRoot $VaultRoot
}

Export-ModuleMember -Function @(
    "Get-DefaultSigningVaultRoot",
    "Initialize-SigningVault",
    "Resolve-PortableDestinationPath",
    "Get-KeytoolPath",
    "Get-GpgPath",
    "New-SigningApp",
    "Import-SigningApp",
    "Import-CheckInSigning",
    "Get-SigningApps",
    "Get-SigningApp",
    "Test-SigningApp",
    "Update-SigningAppMetadata",
    "Get-GitHubSecretEntries",
    "Get-SigningRecoveryRecord",
    "Export-SigningAppBackup",
    "Assert-PortableBackupPassword",
    "Export-PortableSigningVault",
    "Test-PortableSigningVaultBackup",
    "Import-PortableSigningVault",
    "Export-PortableSigningManagerBundle"
)
