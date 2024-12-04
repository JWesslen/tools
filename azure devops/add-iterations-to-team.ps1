[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $ProjectName,
    [Parameter(Mandatory = $true)]
    [string]
    $OrganizationName
)

$organization = "https://dev.azure.com/$OrganizationName"

$createdIterations = az boards iteration project list --organization $organization --project $ProjectName --depth 4 --output json | ConvertFrom-Json

# Get all IDs of the created iterations
$iterationIds = @()
foreach ($iteration in $createdIterations.children) {
    foreach ($child in $iteration.children) {
        $iterationIds += $child.identifier
    }
}

# Get team IDs to add iterations for
$teams = az devops team list --organization $organization --project $ProjectName --output json | ConvertFrom-Json

# Get IDs for already existing iterations for each team in hash table
$existingIterationIds = @{}
foreach ($team in $teams) {
    $existingIterations = az boards iteration team list --organization $organization --project $ProjectName --team $team.id --output json | ConvertFrom-Json
    $existingIterationIds[$team.id] = @()
    foreach ($iteration in $existingIterations) {
        $existingIterationIds[$team.id] += $iteration.id
    }
}

# Add iterations to the teams except the ones already existing
foreach ($team in $teams) {
    $teamId = $team.id
    $iterationsToAdd = $iterationIds | Where-Object { $existingIterationIds[$teamId] -notcontains $_ }
    foreach ($iterationId in $iterationsToAdd) {
        Write-Host "Adding iteration $iterationId to team $teamId" -ForegroundColor Yellow
        az boards iteration team add --organization $organization --project $ProjectName --team $teamId --id $iterationId
    }
}
