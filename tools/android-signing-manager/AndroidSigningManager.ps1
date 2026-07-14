param(
    [ValidateSet("Gui", "List", "ImportCheckIn", "Verify")]
    [string]$Command = "Gui",
    [string]$VaultRoot = "",
    [string]$ProjectPath = "",
    [string]$PackageId = ""
)

$ErrorActionPreference = "Stop"
$managerRoot = $PSScriptRoot
$modulePath = Join-Path $managerRoot "SigningVault.psm1"
$stringsPath = Join-Path $managerRoot "strings.zh-CN.json"

Import-Module $modulePath -Force

if ([string]::IsNullOrWhiteSpace($VaultRoot)) {
    $VaultRoot = Get-DefaultSigningVaultRoot
}
$VaultRoot = [IO.Path]::GetFullPath($VaultRoot)

function Get-UiStrings {
    if (-not (Test-Path -LiteralPath $stringsPath)) {
        throw "UI language file is missing: $stringsPath"
    }
    return Get-Content `
        -LiteralPath $stringsPath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json
}

function Write-AppSummary {
    param(
        [Parameter(Mandatory = $true)]$App
    )

    [PSCustomObject]@{
        AppName = $App.appName
        PackageId = $App.packageId
        Repository = $App.repository
        Alias = $App.alias
        CertificateSha256 = $App.certificateSha256
        LatestVersion = $App.latestVersion
        VaultDirectory = $App.AppDirectory
    } | Format-List
}

switch ($Command) {
    "List" {
        Get-SigningApps -VaultRoot $VaultRoot |
            Select-Object `
                appName,
                packageId,
                repository,
                alias,
                certificateSha256,
                latestVersion |
            Format-Table -AutoSize
        return
    }
    "ImportCheckIn" {
        if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
            throw "ProjectPath is required for ImportCheckIn."
        }
        $app = Import-CheckInSigning `
            -ProjectPath $ProjectPath `
            -VaultRoot $VaultRoot
        $verification = Test-SigningApp `
            -PackageId $app.packageId `
            -VaultRoot $VaultRoot
        if (-not $verification.Matches) {
            throw "Imported Check in certificate fingerprint does not match."
        }
        Write-AppSummary -App $app
        return
    }
    "Verify" {
        if ([string]::IsNullOrWhiteSpace($PackageId)) {
            throw "PackageId is required for Verify."
        }
        Test-SigningApp `
            -PackageId $PackageId `
            -VaultRoot $VaultRoot |
            Format-List
        return
    }
}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne "STA") {
    throw (
        "The GUI requires an STA PowerShell session. Start it with " +
        "Start-AndroidSigningManager.cmd."
    )
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$strings = Get-UiStrings
$script:ClipboardTimer = $null
$script:ClipboardSecret = $null
$script:MainStatusLabel = $null

function Show-UiError {
    param(
        [Parameter(Mandatory = $true)][string]$Message
    )

    [Windows.Forms.MessageBox]::Show(
        $Message,
        $strings.ErrorTitle,
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Show-UiInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Message
    )

    [Windows.Forms.MessageBox]::Show(
        $Message,
        $strings.ErrorTitle,
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Set-StatusText {
    param(
        [Parameter(Mandatory = $true)][string]$Text
    )

    if ($null -ne $script:MainStatusLabel) {
        $script:MainStatusLabel.Text = $Text
    }
}

function Clear-SensitiveClipboard {
    if ($null -ne $script:ClipboardTimer) {
        $script:ClipboardTimer.Stop()
        $script:ClipboardTimer.Dispose()
        $script:ClipboardTimer = $null
    }
    if ($null -ne $script:ClipboardSecret) {
        try {
            if ([Windows.Forms.Clipboard]::ContainsText()) {
                $current = [Windows.Forms.Clipboard]::GetText()
                if ($current -ceq $script:ClipboardSecret) {
                    [Windows.Forms.Clipboard]::Clear()
                }
                $current = $null
            }
        } catch {
        }
        $script:ClipboardSecret = $null
        Set-StatusText -Text $strings.StatusClipboardCleared
    }
}

function Set-SensitiveClipboard {
    param(
        [Parameter(Mandatory = $true)][string]$Text
    )

    Clear-SensitiveClipboard
    [Windows.Forms.Clipboard]::SetText($Text)
    $script:ClipboardSecret = $Text
    $script:ClipboardTimer = New-Object Windows.Forms.Timer
    $script:ClipboardTimer.Interval = 60000
    $script:ClipboardTimer.Add_Tick({
        Clear-SensitiveClipboard
    })
    $script:ClipboardTimer.Start()
    Set-StatusText -Text $strings.StatusCopied
}

function New-DialogLabel {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$Top
    )

    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.Left = 18
    $label.Top = $Top + 4
    $label.Width = 150
    return $label
}

function New-DialogTextBox {
    param(
        [Parameter(Mandatory = $true)][int]$Top,
        [string]$Text = "",
        [bool]$ReadOnly = $false,
        [bool]$Password = $false,
        [int]$Width = 390
    )

    $textBox = New-Object Windows.Forms.TextBox
    $textBox.Left = 175
    $textBox.Top = $Top
    $textBox.Width = $Width
    $textBox.Text = $Text
    $textBox.ReadOnly = $ReadOnly
    if ($Password) {
        $textBox.UseSystemPasswordChar = $true
    }
    return $textBox
}

function Show-MetadataDialog {
    param(
        [ValidateSet("New", "Edit")][string]$Mode,
        $Existing
    )

    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = if ($Mode -eq "New") {
        $strings.CreateTitle
    } else {
        $strings.EditTitle
    }
    $dialog.ClientSize = New-Object Drawing.Size(610, 410)
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.StartPosition = "CenterParent"
    $dialog.Font = New-Object Drawing.Font("Segoe UI", 9)
    $dialog.AutoScaleMode = "None"

    $initial = @{
        AppName = ""
        PackageId = ""
        Repository = ""
        SecretPrefix = ""
        Alias = "release"
        Version = ""
        ProjectPath = ""
    }
    if ($null -ne $Existing) {
        $initial.AppName = [string]$Existing.appName
        $initial.PackageId = [string]$Existing.packageId
        $initial.Repository = [string]$Existing.repository
        $initial.SecretPrefix = [string]$Existing.secretPrefix
        $initial.Alias = [string]$Existing.alias
        $initial.Version = [string]$Existing.latestVersion
        $initial.ProjectPath = [string]$Existing.projectPath
    }

    $rows = @(
        @{ Key = "AppName"; Label = $strings.AppName },
        @{ Key = "PackageId"; Label = $strings.PackageId },
        @{ Key = "Repository"; Label = $strings.Repository },
        @{ Key = "SecretPrefix"; Label = $strings.SecretPrefix },
        @{ Key = "Alias"; Label = $strings.Alias },
        @{ Key = "Version"; Label = $strings.Version },
        @{ Key = "ProjectPath"; Label = $strings.ProjectPath }
    )
    $controls = @{}
    $top = 20
    foreach ($row in $rows) {
        $dialog.Controls.Add(
            (New-DialogLabel -Text $row.Label -Top $top)
        )
        $textWidth = if ($row.Key -eq "ProjectPath") { 310 } else { 390 }
        $readOnly = (
            $Mode -eq "Edit" -and
            $row.Key -in @("PackageId", "Alias")
        )
        $textBox = New-DialogTextBox `
            -Top $top `
            -Text $initial[$row.Key] `
            -ReadOnly $readOnly `
            -Width $textWidth
        $dialog.Controls.Add($textBox)
        $controls[$row.Key] = $textBox
        if ($row.Key -eq "ProjectPath") {
            $browseButton = New-Object Windows.Forms.Button
            $browseButton.Text = $strings.Browse
            $browseButton.Left = 495
            $browseButton.Top = $top - 1
            $browseButton.Width = 70
            $browseButton.Height = 27
            $browseButton.Add_Click({
                $folderDialog = New-Object Windows.Forms.FolderBrowserDialog
                $folderDialog.Description = $strings.SelectProjectFolder
                if ($folderDialog.ShowDialog($dialog) -eq "OK") {
                    $controls.ProjectPath.Text = $folderDialog.SelectedPath
                }
                $folderDialog.Dispose()
            })
            $dialog.Controls.Add($browseButton)
        }
        $top += 45
    }

    $okButton = New-Object Windows.Forms.Button
    $okButton.Text = if ($Mode -eq "New") {
        $strings.Create
    } else {
        $strings.Save
    }
    $okButton.Left = 390
    $okButton.Top = 350
    $okButton.Width = 85
    $okButton.Height = 30
    $okButton.Add_Click({
        try {
            $result = [PSCustomObject]@{
                AppName = $controls.AppName.Text.Trim()
                PackageId = $controls.PackageId.Text.Trim()
                Repository = $controls.Repository.Text.Trim()
                SecretPrefix = (
                    $controls.SecretPrefix.Text.Trim().ToUpperInvariant()
                )
                Alias = $controls.Alias.Text.Trim()
                LatestVersion = $controls.Version.Text.Trim()
                ProjectPath = $controls.ProjectPath.Text.Trim()
            }
            if ([string]::IsNullOrWhiteSpace($result.AppName) -or
                [string]::IsNullOrWhiteSpace($result.PackageId) -or
                [string]::IsNullOrWhiteSpace($result.SecretPrefix) -or
                [string]::IsNullOrWhiteSpace($result.Alias)) {
                throw "Required fields are incomplete."
            }
            $dialog.Tag = $result
            $dialog.DialogResult = "OK"
            $dialog.Close()
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    })
    $dialog.Controls.Add($okButton)

    $cancelButton = New-Object Windows.Forms.Button
    $cancelButton.Text = $strings.Cancel
    $cancelButton.Left = 485
    $cancelButton.Top = 350
    $cancelButton.Width = 80
    $cancelButton.Height = 30
    $cancelButton.DialogResult = "Cancel"
    $dialog.Controls.Add($cancelButton)
    $dialog.AcceptButton = $okButton
    $dialog.CancelButton = $cancelButton

    $result = $null
    if ($dialog.ShowDialog() -eq "OK") {
        $result = $dialog.Tag
    }
    $dialog.Dispose()
    return $result
}

function Show-ImportDialog {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $strings.ImportTitle
    $dialog.ClientSize = New-Object Drawing.Size(640, 620)
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.StartPosition = "CenterParent"
    $dialog.Font = New-Object Drawing.Font("Segoe UI", 9)
    $dialog.AutoScaleMode = "None"

    $fields = @(
        @{ Key = "AppName"; Label = $strings.AppName; Password = $false },
        @{ Key = "PackageId"; Label = $strings.PackageId; Password = $false },
        @{ Key = "Repository"; Label = $strings.Repository; Password = $false },
        @{ Key = "SecretPrefix"; Label = $strings.SecretPrefix; Password = $false },
        @{ Key = "Alias"; Label = $strings.Alias; Password = $false },
        @{ Key = "Version"; Label = $strings.Version; Password = $false },
        @{ Key = "ProjectPath"; Label = $strings.ProjectPath; Password = $false },
        @{ Key = "KeystorePath"; Label = $strings.KeystorePath; Password = $false },
        @{ Key = "StorePassword"; Label = $strings.StorePassword; Password = $true },
        @{ Key = "KeyPassword"; Label = $strings.KeyPassword; Password = $true }
    )
    $controls = @{}
    $top = 18
    foreach ($field in $fields) {
        $dialog.Controls.Add(
            (New-DialogLabel -Text $field.Label -Top $top)
        )
        $needsBrowse = $field.Key -in @("ProjectPath", "KeystorePath")
        $width = if ($needsBrowse) { 330 } else { 420 }
        $defaultText = if ($field.Key -eq "Alias") { "release" } else { "" }
        $textBox = New-DialogTextBox `
            -Top $top `
            -Text $defaultText `
            -Password $field.Password `
            -Width $width
        $dialog.Controls.Add($textBox)
        $controls[$field.Key] = $textBox
        if ($needsBrowse) {
            $browseButton = New-Object Windows.Forms.Button
            $browseButton.Text = $strings.Browse
            $browseButton.Left = 520
            $browseButton.Top = $top - 1
            $browseButton.Width = 75
            $browseButton.Height = 27
            $fieldKey = $field.Key
            $browseButton.Add_Click({
                if ($fieldKey -eq "ProjectPath") {
                    $folderDialog = New-Object Windows.Forms.FolderBrowserDialog
                    $folderDialog.Description = $strings.SelectProjectFolder
                    if ($folderDialog.ShowDialog($dialog) -eq "OK") {
                        $controls.ProjectPath.Text = $folderDialog.SelectedPath
                    }
                    $folderDialog.Dispose()
                } else {
                    $fileDialog = New-Object Windows.Forms.OpenFileDialog
                    $fileDialog.Title = $strings.SelectKeystore
                    $fileDialog.Filter = (
                        "PKCS12 certificate (*.p12;*.pfx)|*.p12;*.pfx|" +
                        "All files (*.*)|*.*"
                    )
                    if ($fileDialog.ShowDialog($dialog) -eq "OK") {
                        $controls.KeystorePath.Text = $fileDialog.FileName
                    }
                    $fileDialog.Dispose()
                }
            }.GetNewClosure())
            $dialog.Controls.Add($browseButton)
        }
        $top += 46
    }

    $hint = New-Object Windows.Forms.Label
    $hint.Text = $strings.PasswordHint
    $hint.Left = 175
    $hint.Top = 485
    $hint.Width = 420
    $hint.Height = 35
    $hint.ForeColor = [Drawing.Color]::DimGray
    $dialog.Controls.Add($hint)

    $okButton = New-Object Windows.Forms.Button
    $okButton.Text = $strings.Import
    $okButton.Left = 420
    $okButton.Top = 550
    $okButton.Width = 80
    $okButton.Height = 30
    $okButton.Add_Click({
        try {
            $keyPassword = $controls.KeyPassword.Text
            if ([string]::IsNullOrWhiteSpace($keyPassword)) {
                $keyPassword = $controls.StorePassword.Text
            }
            $result = [PSCustomObject]@{
                AppName = $controls.AppName.Text.Trim()
                PackageId = $controls.PackageId.Text.Trim()
                Repository = $controls.Repository.Text.Trim()
                SecretPrefix = (
                    $controls.SecretPrefix.Text.Trim().ToUpperInvariant()
                )
                Alias = $controls.Alias.Text.Trim()
                LatestVersion = $controls.Version.Text.Trim()
                ProjectPath = $controls.ProjectPath.Text.Trim()
                KeystorePath = $controls.KeystorePath.Text.Trim()
                StorePassword = $controls.StorePassword.Text
                KeyPassword = $keyPassword
            }
            if ([string]::IsNullOrWhiteSpace($result.AppName) -or
                [string]::IsNullOrWhiteSpace($result.PackageId) -or
                [string]::IsNullOrWhiteSpace($result.SecretPrefix) -or
                [string]::IsNullOrWhiteSpace($result.Alias) -or
                [string]::IsNullOrWhiteSpace($result.KeystorePath) -or
                [string]::IsNullOrWhiteSpace($result.StorePassword)) {
                throw "Required fields are incomplete."
            }
            $dialog.Tag = $result
            $dialog.DialogResult = "OK"
            $dialog.Close()
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    })
    $dialog.Controls.Add($okButton)

    $cancelButton = New-Object Windows.Forms.Button
    $cancelButton.Text = $strings.Cancel
    $cancelButton.Left = 510
    $cancelButton.Top = 550
    $cancelButton.Width = 85
    $cancelButton.Height = 30
    $cancelButton.DialogResult = "Cancel"
    $dialog.Controls.Add($cancelButton)
    $dialog.AcceptButton = $okButton
    $dialog.CancelButton = $cancelButton

    $result = $null
    if ($dialog.ShowDialog() -eq "OK") {
        $result = $dialog.Tag
    }
    foreach ($sensitiveKey in @("StorePassword", "KeyPassword")) {
        $controls[$sensitiveKey].Text = ""
    }
    $dialog.Dispose()
    return $result
}

function Show-PortablePasswordDialog {
    param(
        [bool]$ConfirmPassword = $false
    )

    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $strings.PortablePasswordTitle
    $dialog.ClientSize = New-Object Drawing.Size(
        590,
        $(if ($ConfirmPassword) { 250 } else { 205 })
    )
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.StartPosition = "CenterParent"
    $dialog.Font = New-Object Drawing.Font("Segoe UI", 9)
    $dialog.AutoScaleMode = "None"

    $dialog.Controls.Add(
        (New-DialogLabel `
            -Text $strings.PortablePassword `
            -Top 24)
    )
    $passwordBox = New-DialogTextBox `
        -Top 24 `
        -Password $true `
        -Width 375
    $dialog.Controls.Add($passwordBox)

    $confirmBox = $null
    if ($ConfirmPassword) {
        $dialog.Controls.Add(
            (New-DialogLabel `
                -Text $strings.PortablePasswordConfirm `
                -Top 70)
        )
        $confirmBox = New-DialogTextBox `
            -Top 70 `
            -Password $true `
            -Width 375
        $dialog.Controls.Add($confirmBox)
    }

    $hint = New-Object Windows.Forms.Label
    $hint.Text = $strings.PortablePasswordHint
    $hint.Left = 24
    $hint.Top = if ($ConfirmPassword) { 117 } else { 72 }
    $hint.Width = 535
    $hint.Height = 48
    $hint.ForeColor = [Drawing.Color]::DimGray
    $dialog.Controls.Add($hint)

    $buttonTop = if ($ConfirmPassword) { 190 } else { 145 }
    $okButton = New-Object Windows.Forms.Button
    $okButton.Text = if ($ConfirmPassword) {
        $strings.Backup
    } else {
        $strings.Import
    }
    $okButton.Left = 385
    $okButton.Top = $buttonTop
    $okButton.Width = 85
    $okButton.Height = 30
    $okButton.Add_Click({
        $securePassword = $null
        try {
            if ([string]::IsNullOrWhiteSpace($passwordBox.Text)) {
                throw $strings.PortablePasswordHint
            }
            if ($ConfirmPassword -and
                $passwordBox.Text -cne $confirmBox.Text) {
                throw $strings.PortablePasswordMismatch
            }
            $securePassword = ConvertTo-SecureString `
                -String $passwordBox.Text `
                -AsPlainText `
                -Force
            if ($ConfirmPassword) {
                Assert-PortableBackupPassword `
                    -MasterPassword $securePassword
            }
            $dialog.Tag = $securePassword
            $securePassword = $null
            $dialog.DialogResult = "OK"
            $dialog.Close()
        } catch {
            if ($null -ne $securePassword) {
                $securePassword.Dispose()
            }
            Show-UiError -Message $_.Exception.Message
        }
    })
    $dialog.Controls.Add($okButton)

    $cancelButton = New-Object Windows.Forms.Button
    $cancelButton.Text = $strings.Cancel
    $cancelButton.Left = 480
    $cancelButton.Top = $buttonTop
    $cancelButton.Width = 80
    $cancelButton.Height = 30
    $cancelButton.DialogResult = "Cancel"
    $dialog.Controls.Add($cancelButton)
    $dialog.AcceptButton = $okButton
    $dialog.CancelButton = $cancelButton

    $result = $null
    if ($dialog.ShowDialog() -eq "OK") {
        $result = $dialog.Tag
    }
    $passwordBox.Text = ""
    if ($null -ne $confirmBox) {
        $confirmBox.Text = ""
    }
    $dialog.Dispose()
    return $result
}

function Show-RecoveryDialog {
    param(
        [Parameter(Mandatory = $true)][string]$SelectedPackageId
    )

    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $strings.RecoveryTitle
    $dialog.ClientSize = New-Object Drawing.Size(570, 210)
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.StartPosition = "CenterParent"
    $dialog.Font = New-Object Drawing.Font("Segoe UI", 9)
    $dialog.AutoScaleMode = "None"

    $hint = New-Object Windows.Forms.Label
    $hint.Text = $strings.RecoveryHint
    $hint.Left = 20
    $hint.Top = 22
    $hint.Width = 520
    $hint.Height = 60
    $hint.AutoEllipsis = $true
    $dialog.Controls.Add($hint)

    $copyButton = New-Object Windows.Forms.Button
    $copyButton.Text = $strings.CopyRecovery
    $copyButton.Left = 270
    $copyButton.Top = 115
    $copyButton.Width = 145
    $copyButton.Height = 32
    $copyButton.Add_Click({
        try {
            $record = Get-SigningRecoveryRecord `
                -PackageId $SelectedPackageId `
                -VaultRoot $VaultRoot
            Set-SensitiveClipboard -Text $record
            $record = $null
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    })
    $dialog.Controls.Add($copyButton)

    $doneButton = New-Object Windows.Forms.Button
    $doneButton.Text = $strings.Done
    $doneButton.Left = 430
    $doneButton.Top = 115
    $doneButton.Width = 105
    $doneButton.Height = 32
    $doneButton.DialogResult = "OK"
    $dialog.Controls.Add($doneButton)
    $dialog.AcceptButton = $doneButton
    $dialog.ShowDialog() | Out-Null
    $dialog.Dispose()
}

function Show-SecretsDialog {
    param(
        [Parameter(Mandatory = $true)][string]$SelectedPackageId
    )

    $metadata = Get-SigningApp `
        -PackageId $SelectedPackageId `
        -VaultRoot $VaultRoot
    $entries = @(
        Get-GitHubSecretEntries `
            -PackageId $SelectedPackageId `
            -VaultRoot $VaultRoot
    )
    try {
        $dialog = New-Object Windows.Forms.Form
        $dialog.Text = $strings.SecretsTitle
        $dialog.ClientSize = New-Object Drawing.Size(680, 360)
        $dialog.FormBorderStyle = "FixedDialog"
        $dialog.MaximizeBox = $false
        $dialog.MinimizeBox = $false
        $dialog.StartPosition = "CenterParent"
        $dialog.Font = New-Object Drawing.Font("Segoe UI", 9)
        $dialog.AutoScaleMode = "None"

        $hint = New-Object Windows.Forms.Label
        $hint.Text = $strings.SecretsHint
        $hint.Left = 20
        $hint.Top = 18
        $hint.Width = 630
        $hint.Height = 40
        $dialog.Controls.Add($hint)

        $top = 68
        foreach ($entry in $entries) {
            $nameLabel = New-Object Windows.Forms.Label
            $nameLabel.Text = $entry.Name
            $nameLabel.Left = 25
            $nameLabel.Top = $top + 7
            $nameLabel.Width = 420
            $nameLabel.Font = New-Object Drawing.Font(
                "Consolas",
                10,
                [Drawing.FontStyle]::Regular
            )
            $dialog.Controls.Add($nameLabel)

            $copyButton = New-Object Windows.Forms.Button
            $copyButton.Text = $strings.CopyValue
            $copyButton.Left = 500
            $copyButton.Top = $top
            $copyButton.Width = 130
            $copyButton.Height = 30
            $entryCopy = $entry
            $copyButton.Add_Click({
                Set-SensitiveClipboard -Text $entryCopy.Value
            }.GetNewClosure())
            $dialog.Controls.Add($copyButton)
            $top += 52
        }

        if (-not [string]::IsNullOrWhiteSpace($metadata.repository)) {
            $openButton = New-Object Windows.Forms.Button
            $openButton.Text = $strings.OpenGitHub
            $openButton.Left = 25
            $openButton.Top = 290
            $openButton.Width = 230
            $openButton.Height = 32
            $repository = [string]$metadata.repository
            $openButton.Add_Click({
                Start-Process (
                    "https://github.com/$repository/settings/secrets/actions"
                )
            }.GetNewClosure())
            $dialog.Controls.Add($openButton)
        }

        $doneButton = New-Object Windows.Forms.Button
        $doneButton.Text = $strings.Done
        $doneButton.Left = 530
        $doneButton.Top = 290
        $doneButton.Width = 100
        $doneButton.Height = 32
        $doneButton.DialogResult = "OK"
        $dialog.Controls.Add($doneButton)
        $dialog.AcceptButton = $doneButton
        $dialog.ShowDialog() | Out-Null
        $dialog.Dispose()
    } finally {
        foreach ($entry in $entries) {
            $entry.Value = $null
        }
        $entries = $null
    }
}

function New-ToolbarButton {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][scriptblock]$OnClick,
        [int]$Width = 105
    )

    $button = New-Object Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 32
    $button.Margin = New-Object Windows.Forms.Padding(4, 7, 4, 5)
    $button.FlatStyle = "System"
    $button.Add_Click($OnClick)
    return $button
}

$form = New-Object Windows.Forms.Form
$form.Text = $strings.Title
$form.ClientSize = New-Object Drawing.Size(1000, 690)
$form.MinimumSize = New-Object Drawing.Size(820, 680)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object Drawing.Font("Segoe UI", 9)
$form.AutoScaleMode = "None"

$rootLayout = New-Object Windows.Forms.TableLayoutPanel
$rootLayout.Dock = "Fill"
$rootLayout.ColumnCount = 1
$rootLayout.RowCount = 3
$rootLayout.Margin = New-Object Windows.Forms.Padding(0)
$rootLayout.Padding = New-Object Windows.Forms.Padding(0)
$rootLayout.ColumnStyles.Add(
    (New-Object Windows.Forms.ColumnStyle("Percent", 100))
) | Out-Null
$rootLayout.RowStyles.Add(
    (New-Object Windows.Forms.RowStyle("Absolute", 88))
) | Out-Null
$rootLayout.RowStyles.Add(
    (New-Object Windows.Forms.RowStyle("Percent", 100))
) | Out-Null
$rootLayout.RowStyles.Add(
    (New-Object Windows.Forms.RowStyle("Absolute", 24))
) | Out-Null
$form.Controls.Add($rootLayout)

$toolbar = New-Object Windows.Forms.TableLayoutPanel
$toolbar.Dock = "Fill"
$toolbar.Padding = New-Object Windows.Forms.Padding(5, 0, 5, 0)
$toolbar.ColumnCount = 5
$toolbar.RowCount = 2
$toolbar.GrowStyle = "FixedSize"
for ($columnIndex = 0; $columnIndex -lt 5; $columnIndex++) {
    $toolbar.ColumnStyles.Add(
        (New-Object Windows.Forms.ColumnStyle("Percent", 20))
    ) | Out-Null
}
$toolbar.RowStyles.Add(
    (New-Object Windows.Forms.RowStyle("Percent", 50))
) | Out-Null
$toolbar.RowStyles.Add(
    (New-Object Windows.Forms.RowStyle("Percent", 50))
) | Out-Null
$rootLayout.Controls.Add($toolbar, 0, 0)

$statusStrip = New-Object Windows.Forms.StatusStrip
$script:MainStatusLabel = New-Object Windows.Forms.ToolStripStatusLabel
$script:MainStatusLabel.Text = $strings.StatusReady
$script:MainStatusLabel.Spring = $true
$script:MainStatusLabel.TextAlign = "MiddleLeft"
$vaultStatus = New-Object Windows.Forms.ToolStripStatusLabel
$vaultStatus.Text = "$($strings.VaultLocation): $VaultRoot"
$statusStrip.Items.Add($script:MainStatusLabel) | Out-Null
$statusStrip.Items.Add($vaultStatus) | Out-Null
$statusStrip.Dock = "Fill"
$statusStrip.SizingGrip = $false
$rootLayout.Controls.Add($statusStrip, 0, 2)

$split = New-Object Windows.Forms.SplitContainer
$split.Dock = "Fill"
$split.Orientation = "Horizontal"
$rootLayout.Controls.Add($split, 0, 1)

$grid = New-Object Windows.Forms.DataGridView
$grid.Dock = "Fill"
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.AutoGenerateColumns = $false
$grid.AutoSizeColumnsMode = "Fill"
$grid.BackgroundColor = [Drawing.Color]::White
$grid.BorderStyle = "FixedSingle"
$grid.SelectionMode = "FullRowSelect"
$grid.MultiSelect = $false
$grid.RowHeadersVisible = $false
$split.Panel1.Controls.Add($grid)

foreach ($columnDefinition in @(
    @{ Name = "AppName"; Header = $strings.AppName; Property = "AppName"; Fill = 15 },
    @{ Name = "PackageId"; Header = $strings.PackageId; Property = "PackageId"; Fill = 24 },
    @{ Name = "Repository"; Header = $strings.Repository; Property = "Repository"; Fill = 20 },
    @{ Name = "Version"; Header = $strings.Version; Property = "Version"; Fill = 9 },
    @{ Name = "Alias"; Header = $strings.Alias; Property = "Alias"; Fill = 10 },
    @{ Name = "Fingerprint"; Header = $strings.Fingerprint; Property = "Fingerprint"; Fill = 22 }
)) {
    $column = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $column.Name = $columnDefinition.Name
    $column.HeaderText = $columnDefinition.Header
    $column.DataPropertyName = $columnDefinition.Property
    $column.FillWeight = $columnDefinition.Fill
    $grid.Columns.Add($column) | Out-Null
}

$details = New-Object Windows.Forms.TableLayoutPanel
$details.Dock = "Fill"
$details.Padding = New-Object Windows.Forms.Padding(10)
$details.ColumnCount = 4
$details.RowCount = 5
$details.ColumnStyles.Add(
    (New-Object Windows.Forms.ColumnStyle("Absolute", 115))
)
$details.ColumnStyles.Add(
    (New-Object Windows.Forms.ColumnStyle("Percent", 50))
)
$details.ColumnStyles.Add(
    (New-Object Windows.Forms.ColumnStyle("Absolute", 115))
)
$details.ColumnStyles.Add(
    (New-Object Windows.Forms.ColumnStyle("Percent", 50))
)
$split.Panel2.Controls.Add($details)

$detailValues = @{}
function Add-DetailField {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int]$Row,
        [Parameter(Mandatory = $true)][int]$Column,
        [int]$ColumnSpan = 1
    )

    $labelControl = New-Object Windows.Forms.Label
    $labelControl.Text = $Label
    $labelControl.Dock = "Fill"
    $labelControl.TextAlign = "MiddleLeft"
    $details.Controls.Add($labelControl, $Column, $Row)

    $valueControl = New-Object Windows.Forms.TextBox
    $valueControl.ReadOnly = $true
    $valueControl.Dock = "Fill"
    $valueControl.BorderStyle = "FixedSingle"
    $details.Controls.Add($valueControl, $Column + 1, $Row)
    if ($ColumnSpan -gt 1) {
        $details.SetColumnSpan($valueControl, $ColumnSpan)
    }
    $detailValues[$Key] = $valueControl
}

Add-DetailField `
    -Key "AppName" `
    -Label $strings.AppName `
    -Row 0 `
    -Column 0
Add-DetailField `
    -Key "PackageId" `
    -Label $strings.PackageId `
    -Row 0 `
    -Column 2
Add-DetailField `
    -Key "Repository" `
    -Label $strings.Repository `
    -Row 1 `
    -Column 0
Add-DetailField `
    -Key "Version" `
    -Label $strings.Version `
    -Row 1 `
    -Column 2
Add-DetailField `
    -Key "Alias" `
    -Label $strings.Alias `
    -Row 2 `
    -Column 0
Add-DetailField `
    -Key "SecretPrefix" `
    -Label $strings.SecretPrefix `
    -Row 2 `
    -Column 2
Add-DetailField `
    -Key "Fingerprint" `
    -Label $strings.Fingerprint `
    -Row 3 `
    -Column 0 `
    -ColumnSpan 3
Add-DetailField `
    -Key "ProjectPath" `
    -Label $strings.ProjectPath `
    -Row 4 `
    -Column 0 `
    -ColumnSpan 3

$script:GridData = $null

function Get-SelectedPackageId {
    if ($grid.SelectedRows.Count -ne 1) {
        return $null
    }
    return [string]$grid.SelectedRows[0].Cells["PackageId"].Value
}

function Update-Details {
    $selectedPackageId = Get-SelectedPackageId
    foreach ($control in $detailValues.Values) {
        $control.Text = ""
    }
    if ([string]::IsNullOrWhiteSpace($selectedPackageId)) {
        return
    }
    try {
        $metadata = Get-SigningApp `
            -PackageId $selectedPackageId `
            -VaultRoot $VaultRoot
        $detailValues.AppName.Text = [string]$metadata.appName
        $detailValues.PackageId.Text = [string]$metadata.packageId
        $detailValues.Repository.Text = [string]$metadata.repository
        $detailValues.Version.Text = [string]$metadata.latestVersion
        $detailValues.Alias.Text = [string]$metadata.alias
        $detailValues.SecretPrefix.Text = [string]$metadata.secretPrefix
        $detailValues.Fingerprint.Text = [string]$metadata.certificateSha256
        $detailValues.ProjectPath.Text = [string]$metadata.projectPath
    } catch {
        Set-StatusText -Text $_.Exception.Message
    }
}

function Refresh-Grid {
    param(
        [string]$SelectPackageId = ""
    )

    $rows = New-Object System.Collections.ArrayList
    foreach ($app in @(Get-SigningApps -VaultRoot $VaultRoot)) {
        $fingerprint = [string]$app.certificateSha256
        if ($fingerprint.Length -gt 16) {
            $fingerprint = $fingerprint.Substring(0, 16) + "..."
        }
        $lastVerified = [string]$app.lastVerifiedAtUtc
        if (-not [string]::IsNullOrWhiteSpace($lastVerified)) {
            try {
                $lastVerified = (
                    [DateTime]::Parse($lastVerified).ToLocalTime()
                ).ToString("yyyy-MM-dd HH:mm")
            } catch {
            }
        }
        $rows.Add([PSCustomObject]@{
            AppName = [string]$app.appName
            PackageId = [string]$app.packageId
            Repository = [string]$app.repository
            Version = [string]$app.latestVersion
            Alias = [string]$app.alias
            Fingerprint = $fingerprint
            LastVerified = $lastVerified
        }) | Out-Null
    }
    $script:GridData = $rows
    $grid.DataSource = $null
    $grid.DataSource = $script:GridData

    if ($grid.Rows.Count -eq 0) {
        Set-StatusText -Text $strings.NoRecords
        Update-Details
        return
    }

    $rowToSelect = 0
    if (-not [string]::IsNullOrWhiteSpace($SelectPackageId)) {
        for ($index = 0; $index -lt $grid.Rows.Count; $index++) {
            if ([string]$grid.Rows[$index].Cells["PackageId"].Value -eq
                $SelectPackageId) {
                $rowToSelect = $index
                break
            }
        }
    }
    $grid.ClearSelection()
    $grid.Rows[$rowToSelect].Selected = $true
    $grid.CurrentCell = $grid.Rows[$rowToSelect].Cells["AppName"]
    Set-StatusText -Text $strings.StatusReady
    Update-Details
}

$grid.Add_SelectionChanged({
    Update-Details
})

$newButton = New-ToolbarButton `
    -Text $strings.NewCertificate `
    -Width 105 `
    -OnClick {
        try {
            $input = Show-MetadataDialog -Mode "New"
            if ($null -eq $input) {
                return
            }
            $app = New-SigningApp `
                -AppName $input.AppName `
                -PackageId $input.PackageId `
                -Repository $input.Repository `
                -SecretPrefix $input.SecretPrefix `
                -Alias $input.Alias `
                -LatestVersion $input.LatestVersion `
                -ProjectPath $input.ProjectPath `
                -VaultRoot $VaultRoot
            Refresh-Grid -SelectPackageId $app.packageId
            Show-UiInfo -Message $strings.CreateSuccess
            Show-RecoveryDialog `
                -SelectedPackageId $app.packageId
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    }
$toolbar.Controls.Add($newButton)

$importButton = New-ToolbarButton `
    -Text $strings.ImportCertificate `
    -Width 105 `
    -OnClick {
        $input = $null
        try {
            $input = Show-ImportDialog
            if ($null -eq $input) {
                return
            }
            $app = Import-SigningApp `
                -AppName $input.AppName `
                -PackageId $input.PackageId `
                -Repository $input.Repository `
                -SecretPrefix $input.SecretPrefix `
                -Alias $input.Alias `
                -KeystorePath $input.KeystorePath `
                -StorePassword $input.StorePassword `
                -KeyPassword $input.KeyPassword `
                -LatestVersion $input.LatestVersion `
                -ProjectPath $input.ProjectPath `
                -VaultRoot $VaultRoot
            Refresh-Grid -SelectPackageId $app.packageId
            Show-UiInfo -Message $strings.ImportSuccess
            Show-RecoveryDialog `
                -SelectedPackageId $app.packageId
        } catch {
            Show-UiError -Message $_.Exception.Message
        } finally {
            if ($null -ne $input) {
                $input.StorePassword = $null
                $input.KeyPassword = $null
            }
        }
    }
$toolbar.Controls.Add($importButton)

$editButton = New-ToolbarButton `
    -Text $strings.EditRecord `
    -Width 95 `
    -OnClick {
        try {
            $selectedPackageId = Get-SelectedPackageId
            if ([string]::IsNullOrWhiteSpace($selectedPackageId)) {
                Set-StatusText -Text $strings.StatusNoSelection
                return
            }
            $existing = Get-SigningApp `
                -PackageId $selectedPackageId `
                -VaultRoot $VaultRoot
            $input = Show-MetadataDialog `
                -Mode "Edit" `
                -Existing $existing
            if ($null -eq $input) {
                return
            }
            Update-SigningAppMetadata `
                -PackageId $selectedPackageId `
                -AppName $input.AppName `
                -Repository $input.Repository `
                -SecretPrefix $input.SecretPrefix `
                -LatestVersion $input.LatestVersion `
                -ProjectPath $input.ProjectPath `
                -VaultRoot $VaultRoot |
                Out-Null
            Refresh-Grid -SelectPackageId $selectedPackageId
            Show-UiInfo -Message $strings.EditSuccess
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    }
$toolbar.Controls.Add($editButton)

$verifyButton = New-ToolbarButton `
    -Text $strings.Verify `
    -Width 90 `
    -OnClick {
        try {
            $selectedPackageId = Get-SelectedPackageId
            if ([string]::IsNullOrWhiteSpace($selectedPackageId)) {
                Set-StatusText -Text $strings.StatusNoSelection
                return
            }
            $result = Test-SigningApp `
                -PackageId $selectedPackageId `
                -VaultRoot $VaultRoot
            if (-not $result.Matches) {
                throw $strings.VerifyFailed
            }
            Refresh-Grid -SelectPackageId $selectedPackageId
            Show-UiInfo -Message $strings.VerifySuccess
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    }
$toolbar.Controls.Add($verifyButton)

$secretsButton = New-ToolbarButton `
    -Text $strings.GitHubSecrets `
    -Width 115 `
    -OnClick {
        try {
            $selectedPackageId = Get-SelectedPackageId
            if ([string]::IsNullOrWhiteSpace($selectedPackageId)) {
                Set-StatusText -Text $strings.StatusNoSelection
                return
            }
            Show-SecretsDialog `
                -SelectedPackageId $selectedPackageId
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    }
$toolbar.Controls.Add($secretsButton)

$recoveryButton = New-ToolbarButton `
    -Text $strings.RecoveryRecord `
    -Width 100 `
    -OnClick {
        try {
            $selectedPackageId = Get-SelectedPackageId
            if ([string]::IsNullOrWhiteSpace($selectedPackageId)) {
                Set-StatusText -Text $strings.StatusNoSelection
                return
            }
            Show-RecoveryDialog `
                -SelectedPackageId $selectedPackageId
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    }
$toolbar.Controls.Add($recoveryButton)

$backupButton = New-ToolbarButton `
    -Text $strings.Backup `
    -Width 115 `
    -OnClick {
        $masterPassword = $null
        try {
            $folderDialog = New-Object Windows.Forms.FolderBrowserDialog
            $folderDialog.Description = $strings.SelectBackupFolder
            if ($folderDialog.ShowDialog($form) -ne "OK") {
                $folderDialog.Dispose()
                return
            }
            $destination = $folderDialog.SelectedPath
            $folderDialog.Dispose()
            $masterPassword = Show-PortablePasswordDialog `
                -ConfirmPassword $true
            if ($null -eq $masterPassword) {
                return
            }
            Set-StatusText -Text $strings.PortableExportWorking
            $form.UseWaitCursor = $true
            [Windows.Forms.Application]::DoEvents()
            $bundle = Export-PortableSigningManagerBundle `
                -DestinationRoot $destination `
                -MasterPassword $masterPassword `
                -VaultRoot $VaultRoot
            Show-UiInfo -Message (
                $strings.BackupSuccess +
                "`n`n软件数量: $($bundle.AppCount)" +
                "`n保存位置: $($bundle.BundlePath)"
            )
        } catch {
            Show-UiError -Message $_.Exception.Message
        } finally {
            $form.UseWaitCursor = $false
            if ($null -ne $masterPassword) {
                $masterPassword.Dispose()
            }
            Set-StatusText -Text $strings.StatusReady
        }
    }
$toolbar.Controls.Add($backupButton)

$restoreButton = New-ToolbarButton `
    -Text $strings.RestorePortable `
    -Width 115 `
    -OnClick {
        $masterPassword = $null
        try {
            $fileDialog = New-Object Windows.Forms.OpenFileDialog
            $fileDialog.Title = $strings.SelectPortableBackup
            $fileDialog.Filter = $strings.PortableBackupFilter
            if ($fileDialog.ShowDialog($form) -ne "OK") {
                $fileDialog.Dispose()
                return
            }
            $backupPath = $fileDialog.FileName
            $fileDialog.Dispose()
            $masterPassword = Show-PortablePasswordDialog `
                -ConfirmPassword $false
            if ($null -eq $masterPassword) {
                return
            }
            Set-StatusText -Text $strings.PortableRestoreWorking
            $form.UseWaitCursor = $true
            [Windows.Forms.Application]::DoEvents()
            $result = Import-PortableSigningVault `
                -BackupPath $backupPath `
                -MasterPassword $masterPassword `
                -VaultRoot $VaultRoot
            Refresh-Grid
            Show-UiInfo -Message (
                $strings.RestoreSuccess +
                "`n`n新增软件: $($result.RestoredApps)" +
                "`n已存在并验证: $($result.ExistingApps)" +
                "`n恢复凭据: $($result.CredentialCount)"
            )
        } catch {
            Show-UiError -Message $_.Exception.Message
        } finally {
            $form.UseWaitCursor = $false
            if ($null -ne $masterPassword) {
                $masterPassword.Dispose()
            }
            Set-StatusText -Text $strings.StatusReady
        }
    }
$toolbar.Controls.Add($restoreButton)

$openVaultButton = New-ToolbarButton `
    -Text $strings.OpenVault `
    -Width 100 `
    -OnClick {
        try {
            Initialize-SigningVault -VaultRoot $VaultRoot | Out-Null
            Start-Process -FilePath "explorer.exe" -ArgumentList @($VaultRoot)
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    }
$toolbar.Controls.Add($openVaultButton)

$refreshButton = New-ToolbarButton `
    -Text $strings.Refresh `
    -Width 70 `
    -OnClick {
        try {
            Refresh-Grid -SelectPackageId (Get-SelectedPackageId)
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    }
$toolbar.Controls.Add($refreshButton)

$form.Add_FormClosing({
    Clear-SensitiveClipboard
})

$form.Add_Shown({
    $split.Panel1MinSize = 250
    $split.Panel2MinSize = 170
    $availableHeight = $split.Height - $split.SplitterWidth
    $split.SplitterDistance = [Math]::Min(
        385,
        [Math]::Max(250, $availableHeight - 170)
    )
})

Initialize-SigningVault -VaultRoot $VaultRoot | Out-Null
Refresh-Grid
[Windows.Forms.Application]::Run($form)
$form.Dispose()
