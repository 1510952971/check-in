param(
    [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"
$managerRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = [IO.Path]::GetFullPath(
    (Join-Path $managerRoot "..\..")
)
$modulePath = Join-Path $managerRoot "SigningVault.psm1"
$testRoot = Join-Path `
    $projectRoot `
    "test-artifacts\android-signing-manager-smoke"
$vaultRoot = Join-Path $testRoot "vault"
$backupRoot = Join-Path $testRoot "backup"
$restoreVaultRoot = Join-Path $testRoot "restored-vault"
$portableRoot = Join-Path $testRoot "portable"
$packageId = "com.example.signingmanagersmoke"
$credentialTarget = "AndroidSigningManager:$packageId"
$masterPassword = ConvertTo-SecureString `
    -String "Smoke-Test-Portable-2026!" `
    -AsPlainText `
    -Force

Import-Module $modulePath -Force

function Remove-TestRoot {
    if (-not (Test-Path -LiteralPath $testRoot)) {
        return
    }
    $allowedRoot = [IO.Path]::GetFullPath(
        (Join-Path $projectRoot "test-artifacts")
    ).TrimEnd("\")
    $resolvedTestRoot = [IO.Path]::GetFullPath(
        $testRoot
    ).TrimEnd("\")
    if (-not $resolvedTestRoot.StartsWith(
        "$allowedRoot\",
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove a test directory outside test-artifacts."
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}

try {
    Remove-TestRoot
    $resolvedSmbPath = Resolve-PortableDestinationPath `
        -Path "smb://nas/backup/Android"
    if ($resolvedSmbPath -ne "\\nas\backup\Android") {
        throw "SMB portable destination conversion failed."
    }
    $invalidPathRejected = $false
    try {
        Resolve-PortableDestinationPath -Path "::{VIRTUAL}" |
            Out-Null
    } catch {
        $invalidPathRejected = $true
    }
    if (-not $invalidPathRejected) {
        throw "A Windows virtual path was accepted as a backup folder."
    }

    $app = New-SigningApp `
        -AppName "Smoke Test" `
        -PackageId $packageId `
        -Repository "example/smoke" `
        -SecretPrefix "SMOKE" `
        -Alias "release" `
        -LatestVersion "1.0.0" `
        -VaultRoot $vaultRoot
    $verification = Test-SigningApp `
        -PackageId $packageId `
        -VaultRoot $vaultRoot
    if (-not $verification.Matches) {
        throw "Certificate fingerprint verification failed."
    }
    $secretNames = @(
        Get-GitHubSecretEntries `
            -PackageId $packageId `
            -VaultRoot $vaultRoot |
            Select-Object -ExpandProperty Name
    )
    $expectedNames = @(
        "SMOKE_KEYSTORE_BASE64",
        "SMOKE_KEYSTORE_PASSWORD",
        "SMOKE_KEY_ALIAS",
        "SMOKE_KEY_PASSWORD"
    )
    if ((Compare-Object $secretNames $expectedNames).Count -ne 0) {
        throw "Generated GitHub secret names are incorrect."
    }
    $backupDirectory = Export-SigningAppBackup `
        -PackageId $packageId `
        -DestinationRoot $backupRoot `
        -VaultRoot $vaultRoot
    foreach ($requiredFile in @(
        "release.p12",
        "metadata.json",
        "certificate.sha256",
        "manifest.sha256",
        "RECOVERY-README.txt"
    )) {
        if (-not (Test-Path -LiteralPath (
            Join-Path $backupDirectory $requiredFile
        ))) {
            throw "Backup file is missing: $requiredFile"
        }
    }

    $bundle = Export-PortableSigningManagerBundle `
        -DestinationRoot $portableRoot `
        -MasterPassword $masterPassword `
        -VaultRoot $vaultRoot
    foreach ($requiredBundleFile in @(
        "SigningVault.psm1",
        "AndroidSigningManager.ps1",
        "Start-AndroidSigningManager.cmd",
        "strings.zh-CN.json",
        "README.md",
        "CHECKSUMS.sha256",
        "vault-backup.asmvault.gpg"
    )) {
        if (-not (Test-Path -LiteralPath (
            Join-Path $bundle.BundlePath $requiredBundleFile
        ))) {
            throw "Portable bundle file is missing: $requiredBundleFile"
        }
    }
    $portableVerification = Test-PortableSigningVaultBackup `
        -BackupPath $bundle.BackupPath `
        -MasterPassword $masterPassword
    if (-not $portableVerification.Valid -or
        $portableVerification.AppCount -ne 1) {
        throw "Portable backup self-verification failed."
    }
    $wrongPassword = ConvertTo-SecureString `
        -String "Wrong-Smoke-Password-2026!" `
        -AsPlainText `
        -Force
    $wrongPasswordRejected = $false
    try {
        Test-PortableSigningVaultBackup `
            -BackupPath $bundle.BackupPath `
            -MasterPassword $wrongPassword |
            Out-Null
    } catch {
        $wrongPasswordRejected = $true
    } finally {
        $wrongPassword.Dispose()
    }
    if (-not $wrongPasswordRejected) {
        throw "The portable backup accepted an incorrect master password."
    }

    [AndroidSigningManager.NativeCredential]::Delete(
        $credentialTarget
    ) | Out-Null
    Remove-Item -LiteralPath $vaultRoot -Recurse -Force

    $restoreResult = Import-PortableSigningVault `
        -BackupPath $bundle.BackupPath `
        -MasterPassword $masterPassword `
        -VaultRoot $restoreVaultRoot
    if ($restoreResult.RestoredApps -ne 1 -or
        $restoreResult.CredentialCount -ne 1) {
        throw "Portable backup restore counts are incorrect."
    }
    $restoredVerification = Test-SigningApp `
        -PackageId $packageId `
        -VaultRoot $restoreVaultRoot
    if (-not $restoredVerification.Matches -or
        $restoredVerification.ActualFingerprint -ne
        $verification.ActualFingerprint) {
        throw "Restored certificate fingerprint verification failed."
    }
    $existingRestoreResult = Import-PortableSigningVault `
        -BackupPath $bundle.BackupPath `
        -MasterPassword $masterPassword `
        -VaultRoot $restoreVaultRoot
    if ($existingRestoreResult.RestoredApps -ne 0 -or
        $existingRestoreResult.ExistingApps -ne 1 -or
        $existingRestoreResult.CredentialCount -ne 1) {
        throw "Existing portable backup restore counts are incorrect."
    }

    [PSCustomObject]@{
        PackageId = $app.packageId
        FingerprintLength = $app.certificateSha256.Length
        Verified = $verification.Matches
        SecretCount = $secretNames.Count
        BackupCreated = $true
        PortableBackupVerified = $portableVerification.Valid
        WrongPasswordRejected = $wrongPasswordRejected
        SmbPathSupported = ($resolvedSmbPath -eq "\\nas\backup\Android")
        VirtualPathRejected = $invalidPathRejected
        PortableBundleCreated = $true
        RestoredApps = $restoreResult.RestoredApps
        ExistingRestoreVerified = (
            $existingRestoreResult.ExistingApps -eq 1
        )
        RestoredFingerprintMatches = $restoredVerification.Matches
    } | Format-List
} finally {
    [AndroidSigningManager.NativeCredential]::Delete(
        $credentialTarget
    ) | Out-Null
    if ($null -ne $masterPassword) {
        $masterPassword.Dispose()
    }
    if (-not $KeepArtifacts) {
        Remove-TestRoot
    }
}
