# This script increments the iterations for a given project in Azure DevOps.
# It requires to have at least one sprint present in the project in the format [Iteration name] > PI 01 > PI 01 Sprint 1
# az cli is required to run this script.
# You can install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
# az devops extension is required to run this script.
# You can install it from https://learn.microsoft.com/en-us/cli/azure/devops/extension?view=azure-cli-latest
# You need to run az login before running the script.
# If the login doesn't work automatically, try setting azure devops PAT with the command:
# $env:AZURE_DEVOPS_EXT_PAT=<your_personal_access_token>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $ProjectName,
    [Parameter(Mandatory = $true)]
    [int]
    $NumberOfPIs = 4,
    [Parameter(Mandatory = $true)]
    [string]
    $OrganizationName
)

$organization = "https://dev.azure.com/$OrganizationName"

# Including IP sprint
$numberOfSprints = 5

# List all iterations
$iterations = az boards iteration project list --organization $organization --project $ProjectName --depth 4 --output json | ConvertFrom-Json
Write-Host "FOUND ITERATIONS:"
Write-Host $iterations
$latestIterationIndex = $iterations.children.Count - 1

# Get the latest iteration
$latestPI = $iterations.children[$latestIterationIndex]
$latestIterationIndex = $latestPI.children.Count - 1
$latestIteration = $latestPI.children[$latestIterationIndex]

# Calculate the start and end date for the new iteration
$lastFinishDate = Get-Date $latestIteration.attributes.finishDate
$newIterationStartDate = $lastFinishDate.AddDays(3)
$newIterationEndDate = $newIterationStartDate.AddDays(11)

# Titles for PIs - PI 01, PI 02 etc.
$newIterationPITitle = "PI " + '{0:d2}' -f ([int]$latestPI.name.SubString(3) + 1)

Write-Host "Creating new iterations..."

# Create new PIs and sprints
$currentPIIndex = [int]$latestPI.name.SubString(3)
$iterationStartDate = $lastFinishDate.AddDays(3)
$iterationEndDate = $newIterationEndDate

for ($i = 0; $i -lt $NumberOfPIs; $i++) {
    $newIterationPITitle = "PI " + '{0:d2}' -f ($currentPIIndex + $i + 1)
    Write-Host "Creating new PI -> $newIterationPITitle" -ForegroundColor Green
    az boards iteration project create --organization $organization --project $ProjectName --name $newIterationPITitle --path "\$ProjectName\Iteration\"
    for ($j = 0; $j -lt $numberOfSprints - 1; $j++) {
        $iterationName = "$newIterationPITitle Sprint $($j + 1)"
        $startDate = $($iterationStartDate.ToString("dddd yyyy-MM-dd"))
        $endDate = $($iterationEndDate.ToString("dddd yyyy-MM-dd"))
        Write-Host "Creating iteration $iterationName $startDate - $endDate" -ForegroundColor Cyan
        
        az boards iteration project create --organization $organization --project $ProjectName --name "$iterationName" --start-date $startDate --finish-date $endDate --path "\$ProjectName\Iteration\$newIterationPITitle"

        $iterationStartDate = $iterationStartDate.AddDays(14)
        $iterationEndDate = $iterationStartDate.AddDays(11)
    }

    $iterationEndDate = $iterationStartDate.AddDays(11)
    
    # Create IP sprint at the end of the PI
    az boards iteration project create --organization $organization --project $ProjectName --name "$newIterationPITitle IP Sprint" --start-date $iterationStartDate --finish-date $iterationEndDate --path "\$ProjectName\Iteration\$newIterationPITitle"
    $iterationStartDate = $iterationStartDate.AddDays(14)
    $iterationEndDate = $iterationStartDate.AddDays(11)
}
