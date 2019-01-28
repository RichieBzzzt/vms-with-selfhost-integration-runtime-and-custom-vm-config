
Param(

    [Parameter(Mandatory=$true)] $BaTemplateFile = 'azuredeploy.json',
    [Parameter(Mandatory=$true)] $BaTemplateParametersFile = 'azuredeploy.parameters.json',
    [Parameter(Mandatory=$true)] $ResourceGroupLocation = 'North Europe',
    [Parameter(Mandatory=$true)] $existingDataFactoryName,
    [Parameter(Mandatory=$true)] $existingDataFactoryResourceGroup,
    [Parameter(Mandatory=$true)] $existingDataFactoryVersion,
    [Parameter(Mandatory=$true)] $IntegrationRuntimeName,
    [Parameter(Mandatory=$true)] $NodeCount,
    [Parameter(Mandatory=$true)] $adminUserName,
    [Parameter(Mandatory=$true)] $adminPassword,
    [Parameter(Mandatory=$true)] $existingVirtualNetworkName,
    [Parameter(Mandatory=$true)] $existingVnetLocation,
    [Parameter(Mandatory=$true)] $existingVnetResourceGroupName,
    [Parameter(Mandatory=$true)] $existingSubnetInYourVnet,
	[Parameter(Mandatory=$true)] $VSTSAccount,
	[Parameter(Mandatory=$true)] $PersonalAccessToken,
	[Parameter(Mandatory=$true)] $PoolName
)
if ([string]::IsNullOrEmpty($(Get-AzureRmContext).Account)) {
    Login-AzureRmAccount
}

$PersonalAccessToken = ConvertTo-SecureString "$PersonalAccessToken" -AsPlainText -Force
$AdminPassword = ConvertTo-SecureString "$vmAdminPassword" -AsPlainText -Force

$OptionalParameters = New-Object -TypeName Hashtable

$OptionalParameters["existingDataFactoryName"] = $existingDataFactoryName
$OptionalParameters["existingDataFactoryResourceGroup"] = $existingDataFactoryResourceGroup
$OptionalParameters["existingDataFactoryVersion"] = $existingDataFactoryVersion
$OptionalParameters["IntegrationRuntimeName"] = $IntegrationRuntimeName
$OptionalParameters["NodeCount"] = $NodeCount
$OptionalParameters["adminUserName"] = $adminUserName
$OptionalParameters["adminPassword"] = $adminPassword
$OptionalParameters["existingVirtualNetworkName"] = $existingVirtualNetworkName
$OptionalParameters["existingVnetLocation"] = $existingVnetLocation
$OptionalParameters["existingVnetResourceGroupName"] = $existingVnetResourceGroupName
$OptionalParameters["existingSubnetInYourVnet"] = $existingSubnetInYourVnet
$OptionalParameters["VSTSAccount"] = $VSTSAccount
$OptionalParameters["PersonalAccessToken"] = $PersonalAccessToken
$OptionalParameters["PoolName"] = $PoolName


# Create or update the resource group using the specified template file and template parameters file
New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force

    New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem ($PSScriptRoot + '\' + $BaTemplateFile)).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                       -ResourceGroupName $ResourceGroupName `
                                       -TemplateFile ($PSScriptRoot + '\' + $BaTemplateFile) `
                                       -TemplateParameterFile ($PSScriptRoot + '\' + $BaTemplateParametersFile) `
                                       -Force -Verbose `
                                       -ErrorVariable ErrorMessages `
                                       @OptionalParameters