
Param(

    [Parameter(Mandatory = $false)] $BaTemplateFile = 'azuredeploy.json',
    [Parameter(Mandatory = $false)] $BaTemplateParametersFile = 'azuredeploy.parameters.json',
    [Parameter(Mandatory = $false)] $ResourceGroupLocation = 'North Europe',
    [Parameter(Mandatory = $true)] $prefix,
    [Parameter(Mandatory = $true)] $ResourceGroupName,
    [Parameter(Mandatory = $true)] $existingDataFactoryName,
    [Parameter(Mandatory = $true)] $existingDataFactoryResourceGroup,
    [Parameter(Mandatory = $true)] $existingDataFactoryVersion,
    [Parameter(Mandatory = $true)] $IntegrationRuntimeName,
    [Parameter(Mandatory = $true)] $NodeCount,
    [Parameter(Mandatory = $true)] $adminUserName,
    [Parameter(Mandatory = $true)] $adminPassword,
    [Parameter(Mandatory = $true)] $vmSize,
    [Parameter(Mandatory = $true)] $osDiskSizeInGB,
    [Parameter(Mandatory = $true)] $existingVirtualNetworkName,
    [Parameter(Mandatory = $true)] $existingVnetLocation,
    [Parameter(Mandatory = $true)] $existingVnetResourceGroupName,
    [Parameter(Mandatory = $true)] $existingSubnetInYourVnet
)
if ([string]::IsNullOrEmpty($(Get-AzureRmContext).Account)) {
    Add-AzureRmAccount
}
$AdminPassword = ConvertTo-SecureString "$AdminPassword" -AsPlainText -Force

New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force

##upload artifacts for linked templates

$ArtifactStagingDirectory = $PSScriptRoot
$StorageAccountName = 'aeg' + ((Get-AzureRmContext).Subscription.SubscriptionId).Replace('-', '').substring(0, 8)
$StorageAccount = Get-AzureRmStorageAccount -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorVariable noStorageAccountForYou -ErrorAction SilentlyContinue
if ($noStorageAccountForYou) {
    $StorageAccount = New-AzureRmStorageAccount -StorageAccountName $StorageAccountName -Type 'Standard_LRS' -ResourceGroupName $ResourceGroupName -Location $ResourceGroupLocation
}
$StorageContainerName = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
$_artifactsLocation = $StorageAccount.Context.BlobEndPoint + $StorageContainerName + '/'
Write-Host "Uploaded to $($_artifactsLocation)"

New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1
$ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}
foreach ($SourcePath in $ArtifactFilePaths) {
    Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($ArtifactStagingDirectory.length + 1) `
        -Container $StorageContainerName -Context $StorageAccount.Context -Force | Out-Null
}
##end upload templates

$OptionalParameters = New-Object -TypeName Hashtable
$OptionalParameters["resourcePrefix"] = $prefix
$OptionalParameters["existingDataFactoryName"] = $existingDataFactoryName
$OptionalParameters["existingDataFactoryResourceGroup"] = $existingDataFactoryResourceGroup
$OptionalParameters["existingDataFactoryVersion"] = $existingDataFactoryVersion
$OptionalParameters["IntegrationRuntimeName"] = $IntegrationRuntimeName
$OptionalParameters["NodeCount"] = $NodeCount
$OptionalParameters["adminUserName"] = $adminUserName
$OptionalParameters["adminPassword"] = $adminPassword
$OptionalParameters["vmSize"] = $vmSize
$OptionalParameters["osDiskSizeInGB"] = $osDiskSizeInGB
$OptionalParameters["existingVirtualNetworkName"] = $existingVirtualNetworkName
$OptionalParameters["existingVnetLocation"] = $existingVnetLocation
$OptionalParameters["existingVnetResourceGroupName"] = $existingVnetResourceGroupName
$OptionalParameters["existingSubnetInYourVnet"] = $existingSubnetInYourVnet
$OptionalParameters["customScriptStorageAccountName"] = $StorageAccountName
$OptionalParameters['customScriptStorageAccountKey'] = (Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName).Value[0]
$OptionalParameters["_artifactsLocation"] = $StorageAccount.Context.BlobEndPoint + $StorageContainerName + '/'
$OptionalParameters['_artifactsLocationSasToken'] = ConvertTo-SecureString -AsPlainText -Force `
(New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(1))

New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem ($PSScriptRoot + '\' + $BaTemplateFile)).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile ($PSScriptRoot + '\' + $BaTemplateFile) `
    -TemplateParameterFile ($PSScriptRoot + '\' + $BaTemplateParametersFile) `
    -Force -Verbose `
    -ErrorVariable ErrorMessages `
    @OptionalParameters 
if ($ErrorMessages) {
    Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
    Write-Host "Uploaded to $($_artifactsLocation)"
}
else{
Remove-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -Force -ErrorAction SilentlyContinue *>&1
}