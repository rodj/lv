. C:\Dropbox\ARj\rjmono\Utils\PowerShell\Speak.ps1

$containerName = "BC3"
$appName = "LoanVision"
$oldVersion = "1.0.0.1932"
$newVersion = "1.0.0.1941"
$appFilePath = "C:\Dropbox\ARj\DevOpsAzure\LoanVision\Rodj_LoanVision_$newVersion.app"

# ------------------ do not forget to create package! --------------------------

# Function to check if the app is installed
function Is-AppInstalled($name, $version) {
    $app = Get-BcContainerAppInfo -containerName $containerName -tenant default | Where-Object { $_.Name -eq $name -and $_.Version -eq $version }
    return $null -ne $app
}

Write-Host "Publishing new version $newVersion..."
Publish-BcContainerApp -containerName $containerName -appFile $appFilePath -skipVerification -syncMode ForceSync

Write-Host "Synchronizing new version..."
Sync-BcContainerApp -containerName $containerName -appName $appName -appVersion $newVersion

Write-Host "Upgrading data..."
Start-BcContainerAppDataUpgrade -containerName $containerName -appName $appName -appVersion $newVersion

if (Is-AppInstalled $appName $oldVersion) {
    Write-Host "Uninstalling old version $oldVersion..."
    Uninstall-BcContainerApp -containerName $containerName -appName $appName -Version $oldVersion -Force
}

Write-Host "Installing new version $newVersion..."
Install-BcContainerApp -containerName $containerName -appName $appName -appVersion $newVersion -Force

Rj-Speak-Text -$pText "Hello"

Write-Host "YOU CAN GO NOW..........Unpublishing old version $oldVersion..."
Unpublish-BcContainerApp -containerName $containerName -name $appName -version $oldVersion

Write-Host "Final app status:"
Get-BcContainerAppInfo -containerName $containerName -tenant default | Where-Object { $_.Name -eq $appName }

Write-Host "Update process completed."