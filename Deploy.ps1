
Param(

    [Parameter(Mandatory=$false)] $BaTemplateFile = 'azuredeploy.json',
    [Parameter(Mandatory=$false)] $BaTemplateParametersFile = 'azuredeploy.parameters.json',
    [Parameter(Mandatory=$false)] $ResourceGroupLocation = 'North Europe',
    [Parameter(Mandatory=$true)] $prefix,
    [Parameter(Mandatory=$true)] $ResourceGroupName,
    [Parameter(Mandatory=$true)] $existingDataFactoryName,
    [Parameter(Mandatory=$true)] $existingDataFactoryResourceGroup,
    [Parameter(Mandatory=$true)] $existingDataFactoryVersion,
    [Parameter(Mandatory=$true)] $IntegrationRuntimeName,
    [Parameter(Mandatory=$true)] $NodeCount,
    [Parameter(Mandatory=$true)] $adminUserName,
    [Parameter(Mandatory=$true)] $adminPassword,
    [Parameter(Mandatory=$true)] $vmSize,
    [Parameter(Mandatory=$true)] $osDiskSizeInGB,
    [Parameter(Mandatory=$true)] $existingVirtualNetworkName,
    [Parameter(Mandatory=$true)] $existingVnetLocation,
    [Parameter(Mandatory=$true)] $existingVnetResourceGroupName,
    [Parameter(Mandatory=$true)] $existingSubnetInYourVnet
)
if ([string]::IsNullOrEmpty($(Get-AzureRmContext).Account)) {
    Add-AzureRmAccount
}
$AdminPassword = ConvertTo-SecureString "$AdminPassword" -AsPlainText -Force

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

# Create or update the resource group using the specified template file and template parameters file
New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force

    New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem ($PSScriptRoot + '\' + $BaTemplateFile)).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                       -ResourceGroupName $ResourceGroupName `
                                       -TemplateFile ($PSScriptRoot + '\' + $BaTemplateFile) `
                                       -TemplateParameterFile ($PSScriptRoot + '\' + $BaTemplateParametersFile) `
                                       -Force -Verbose `
                                       -ErrorVariable ErrorMessages `
                                       @OptionalParameters