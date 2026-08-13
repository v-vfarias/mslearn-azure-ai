# Azure Managed Redis Deployment Script (PowerShell)

# Change the values of these variables as needed

# $rg = "<your-resource-group-name>"  # Resource Group name
# $location = "<your-azure-region>"   # Azure region for the resources

$rg = "rg-exercises"        # Resource Group name
$location = "westus2"       # Azure region for the resources

# ============================================================================
# DON'T CHANGE ANYTHING BELOW THIS LINE.
# ============================================================================

# Generate consistent hash from Azure user object ID (based on az login account)
$user_object_id = az ad signed-in-user show --query "id" -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($user_object_id)) {
    Write-Host "Error: Not authenticated with Azure. Please run: az login"
    exit 1
}
$bytes = [System.Text.Encoding]::UTF8.GetBytes($user_object_id)
$sha1 = [System.Security.Cryptography.SHA1]::Create()
$hashBytes = $sha1.ComputeHash($bytes)
$user_hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 8).ToLower()
$cache_name = "amr-exercise-$user_hash"

# Function to create resource group if it doesn't exist
function Create-ResourceGroup {
    Write-Host "Checking resource group '$rg'..."
    $exists = az group exists --name $rg
    if ($exists -eq "false") {
        az group create --name $rg --location $location 2>$null | Out-Null
        Write-Host "Resource group created: $rg"
    } else {
        Write-Host "Resource group already exists: $rg"
    }
}

# Function to create Azure Managed Redis resource
function Create-RedisResource {
    Create-ResourceGroup
    Write-Host ""

    # Check if the cluster already exists
    $cluster_state = az redisenterprise show --resource-group $rg --name $cache_name --query "provisioningState" -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($cluster_state)) {
        Write-Host "Azure Managed Redis resource already exists: $cache_name (State: $cluster_state)"
        return
    }

    Write-Host "Creating Azure Managed Redis resource '$cache_name'..."

    az redisenterprise create `
        --resource-group $rg `
        --name $cache_name `
        --location $location `
        --sku "Balanced_B0" `
        --public-network-access "Enabled" `
        --no-database `
        --no-wait

    Write-Host "The Azure Managed Redis resource is being created and takes 5-10 minutes to complete."
    Write-Host "You can check the deployment status from the menu later in the exercise."
}

# Function to check deployment status
function Check-DeploymentStatus {
    Write-Host "Checking deployment status..."
    Write-Host ""

    Write-Host "Cluster ($cache_name):"
    $cluster_state = az redisenterprise show --resource-group $rg --name $cache_name --query "provisioningState" -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($cluster_state)) {
        Write-Host "  Provisioning state: $cluster_state"
    } else {
        Write-Host "  Status: Not created"
    }

    Write-Host ""
    Write-Host "Database:"
    $db_state = az redisenterprise database show --resource-group $rg --cluster-name $cache_name --query "provisioningState" -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($db_state)) {
        Write-Host "  Provisioning state: $db_state"
    } else {
        Write-Host "  Status: Not created"
    }
}

# Function to create database and retrieve endpoint and access key
function Create-DatabaseAndGetKey {

    # Check if cluster is provisioned
    $cluster_state = az redisenterprise show --resource-group $rg --name $cache_name --query "provisioningState" -o tsv 2>$null
    if ($cluster_state -ne "Succeeded") {
        $state_display = if ([string]::IsNullOrWhiteSpace($cluster_state)) { "Not created" } else { $cluster_state }
        Write-Host "Error: Cluster is not ready (State: $state_display)."
        Write-Host "Please check the deployment status (option 2) and wait until provisioning succeeds."
        return
    }

    # Check if database already exists
    $db_state = az redisenterprise database show --resource-group $rg --cluster-name $cache_name --query "provisioningState" -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($db_state)) {
        Write-Host "Database already exists (State: $db_state). Enabling access key auth..."
        az redisenterprise database update `
            --resource-group $rg `
            --cluster-name $cache_name `
            --access-keys-auth "Enabled" `
            2>$null | Out-Null
    } else {
        Write-Host "Creating database with access key authentication enabled..."
        az redisenterprise database create `
            --resource-group $rg `
            --cluster-name $cache_name `
            --client-protocol "Encrypted" `
            --clustering-policy "NoCluster" `
            --eviction-policy "AllKeysLRU" `
            --port 10000 `
            --access-keys-auth "Enabled" `
            2>$null | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed to create database."
            return
        }
    }

    Write-Host "Retrieving endpoint and access key..."

    # Get the endpoint (hostname)
    $hostname = az redisenterprise show --resource-group $rg --name $cache_name --query "hostName" -o tsv 2>$null

    # Get the primary access key
    $primaryKey = az redisenterprise database list-keys --cluster-name $cache_name -g $rg --query "primaryKey" -o tsv 2>$null

    # Check if values are empty
    if ([string]::IsNullOrWhiteSpace($hostname) -or [string]::IsNullOrWhiteSpace($primaryKey)) {
        Write-Host ""
        Write-Host "Error: Unable to retrieve endpoint or access key."
        Write-Host "Please check the deployment status to ensure the resource is fully provisioned."
        return
    }

    # Write .env file
    @"
REDIS_HOST=$hostname
REDIS_KEY=$primaryKey
"@ | Set-Content ".env" -NoNewline

    Clear-Host
    Write-Host ""
    Write-Host "Redis Connection Information"
    Write-Host "==========================================================="
    Write-Host "Endpoint: $hostname"
    Write-Host "Primary Key: $primaryKey"
    Write-Host ""
    Write-Host "Values have been saved to .env file"
}

# Display menu
function Show-Menu {
    Clear-Host
    Write-Host "====================================================================="
    Write-Host "    Azure Managed Redis Deployment Menu"
    Write-Host "====================================================================="
    Write-Host "Resource Group: $rg"
    Write-Host "Cache Name: $cache_name"
    Write-Host "Location: $location"
    Write-Host "====================================================================="
    Write-Host "1. Create Azure Managed Redis resource"
    Write-Host "2. Check deployment status"
    Write-Host "3. Create database and retrieve endpoint and access key"
    Write-Host "4. Exit"
    Write-Host "====================================================================="
}

# Main menu loop
do {
    Show-Menu
    $choice = Read-Host "Please select an option (1-4)"

    switch ($choice) {
        "1" {
            Write-Host ""
            Create-RedisResource
            Write-Host ""
            Read-Host "Press Enter to continue..."
        }
        "2" {
            Write-Host ""
            Check-DeploymentStatus
            Write-Host ""
            Read-Host "Press Enter to continue..."
        }
        "3" {
            Write-Host ""
            Create-DatabaseAndGetKey
            Write-Host ""
            Read-Host "Press Enter to continue..."
        }
        "4" {
            Write-Host "Exiting..."
            Clear-Host
            exit 0
        }
        default {
            Write-Host ""
            Write-Host "Invalid option. Please select 1-4."
            Write-Host ""
            Read-Host "Press Enter to continue..."
        }
    }

    Write-Host ""
} while ($choice -ne "4")