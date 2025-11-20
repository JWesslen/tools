param(
[Parameter(Mandatory=$true)]
[string]$UserObjectId,

[Parameter(Mandatory=$true)]
[string]$SubscriptionId,

[Parameter(Mandatory=$true)]
[string]$VmResourceGroupName,

[Parameter(Mandatory=$true)]
[string]$KeyVaultResourceGroupName,

[Parameter(Mandatory=$true)]
[string]$BastionResourceGroupName,

[Parameter(Mandatory=$true)]
[string]$VmName
)

# Sample usage:
#.\Assign-Bastion-Access.ps1 -UserObjectId "<user-object-id>" -SubscriptionId "<sub-id>" -VmResourceGroupName "<rgName>" -KeyVaultResourceGroupName "<rgName>" -BastionResourceGroupName "<rgName>" -VmName "<vmname>"

# Check if logged in to Azure CLI
Write-Host "Checking Azure CLI login status..." -ForegroundColor Cyan
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not logged in. Initiating Azure CLI login..." -ForegroundColor Yellow
    az login --use-device-code
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to login to Azure CLI"
        exit 1
    }
}

# Set the subscription context
Write-Host "Setting subscription context to $SubscriptionId..." -ForegroundColor Cyan
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set subscription context. Please verify the subscription ID is correct."
    exit 1
}

# Verify the correct subscription is selected
$currentSub = (az account show --query id -o tsv)
if ($currentSub -ne $SubscriptionId) {
    Write-Error "Failed to set the correct subscription. Current: $currentSub, Expected: $SubscriptionId"
    exit 1
}

Write-Host "Successfully set subscription: $SubscriptionId" -ForegroundColor Green

# Fetch VM details to get NIC information
Write-Host "Fetching VM details..." -ForegroundColor Cyan
$vmDetails = az vm show --resource-group $VmResourceGroupName --name $VmName --query "{nicId:networkProfile.networkInterfaces[0].id}" -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to fetch VM details"
    exit 1
}

# Extract NIC name and resource group from the NIC ID
$nicId = $vmDetails.nicId
$nicName = $nicId.Split('/')[-1]
$nicRg = $nicId.Split('/')[4]

Write-Host "Found NIC: $nicName" -ForegroundColor Green

# Fetch NIC details to get VNET information
Write-Host "Fetching NIC details..." -ForegroundColor Cyan
$nicDetails = az network nic show --ids $nicId --query "{vnetId:ipConfigurations[0].subnet.id}" -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to fetch NIC details"
    exit 1
}

# Extract VNET name and resource group from the VNET ID
$vnetId = $nicDetails.vnetId
$vnetName = $vnetId.Split('/')[8]
$vnetRg = $vnetId.Split('/')[4]

Write-Host "Found VNET: $vnetName" -ForegroundColor Green

# Auto-discover Bastion
Write-Host "Discovering Bastion hosts in resource group: $BastionResourceGroupName..." -ForegroundColor Cyan
$bastions = az network bastion list --resource-group $BastionResourceGroupName --query "[].{name:name, rg:resourceGroup}" -o json | ConvertFrom-Json

if ($bastions -and $bastions.Count -gt 0) {
    $BastionName = $bastions[0].name
    Write-Host "Found Bastion: $BastionName" -ForegroundColor Green
} else {
    Write-Error "No Bastion found in resource group $BastionResourceGroupName. Cannot proceed."
    exit 1
}

# Auto-discover KeyVault
Write-Host "Discovering Key Vaults in resource group: $KeyVaultResourceGroupName..." -ForegroundColor Cyan
$keyVaults = az keyvault list --resource-group $KeyVaultResourceGroupName --query "[].name" -o tsv

if ($keyVaults) {
    $KeyVaultName = ($keyVaults -split "`n")[0]
    Write-Host "Found Key Vault: $KeyVaultName" -ForegroundColor Green
} else {
    Write-Error "No Key Vault found in resource group $KeyVaultResourceGroupName. Cannot proceed."
    exit 1
}

Write-Host "Creating role assignments..." -ForegroundColor Cyan

az role assignment create --role "Reader" --assignee $UserObjectId --scope "/subscriptions/$SubscriptionId/resourceGroups/$BastionResourceGroupName/providers/Microsoft.Network/bastionHosts/$BastionName"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Reader role assignment for Bastion"; exit 1 }

az role assignment create --role "Reader" --assignee $UserObjectId --scope "/subscriptions/$SubscriptionId/resourceGroups/$VmResourceGroupName/providers/Microsoft.Compute/virtualMachines/$VmName"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Reader role assignment for VM"; exit 1 }

az role assignment create --role "Reader" --assignee $UserObjectId --scope $nicId
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Reader role assignment for NIC"; exit 1 }

az role assignment create --role "Reader" --assignee $UserObjectId --scope $vnetId
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Reader role assignment for VNET"; exit 1 }

az role assignment create --role "Reader" --assignee $UserObjectId --scope "/subscriptions/$SubscriptionId/resourceGroups/$KeyVaultResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Reader role assignment for Key Vault"; exit 1 }

az role assignment create --role "Key Vault Secrets User" --assignee $UserObjectId --scope "/subscriptions/$SubscriptionId/resourceGroups/$KeyVaultResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Key Vault Secrets User role assignment"; exit 1 }

Write-Host "All role assignments created successfully!" -ForegroundColor Green