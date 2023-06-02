##############################################################################
# This script is intended to apply one tax code to all items in halo
# Why is this useful? In some countries it's common that all items have the same tax code
##############################################################################

# Tax code that will be applied to each item
$TAX_CODE = 1

# Set the Halo connection details
$VaultName = "keyfault-pwsh"
$HaloClientID = Get-AzKeyVaultSecret -VaultName $VaultName -Name "haloclientid" -AsPlainText
$HaloClientSecret = Get-AzKeyVaultSecret -VaultName $VaultName -Name "haloclientsecret" -AsPlainText
$HaloURL = Get-AzKeyVaultSecret -VaultName $VaultName -Name "halourl" -AsPlainText


# Connect to Halo
Connect-HaloAPI -URL $HaloURL -ClientId $HaloClientID -ClientSecret $HaloClientSecret -Scopes "all"


$items = Get-HaloItem
$items = $items | Where-Object -FilterScript { ($_.taxcode -ne $TAX_CODE) -or ($_.taxcodeother -ne $TAX_CODE) }
if ($items.count -gt 0) {
    Write-Host "$($items.count) items need to be adjusted" -ForegroundColor Yellow
}
else {
    Write-Host "No items need to be adjusted $($item.name)" -ForegroundColor Green
}

foreach ($item in $items) {
    Write-Host "Applying correct taxcode to $($item.name)" -ForegroundColor Green
    $item.taxcode = $TAX_CODE
    $item.taxcodeother = $TAX_CODE
    $null = Set-HaloItem -Item $item
    Start-Sleep -seconds 1
}