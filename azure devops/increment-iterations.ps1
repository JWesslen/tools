[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $projectName,
    [Parameter(Mandatory = $true)]
    [int]
    $numberOfPIs = 4,
    [Parameter(Mandatory = $true)]
    [string]
    $organizationName
)

$organization = "https://dev.azure.com/$organizationName"

# Including IP sprint
$numberOfSprints = 5

# List all iterations
$iterations = az boards iteration project list --organization $organization --project $projectName --depth 4 --output json | ConvertFrom-Json
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

for ($i = 0; $i -lt $numberOfPIs; $i++) {
    $newIterationPITitle = "PI " + '{0:d2}' -f ($currentPIIndex + $i + 1)
    Write-Host "Creating new PI -> $newIterationPITitle" -ForegroundColor Green
    az boards iteration project create --organization $organization --project $projectName --name $newIterationPITitle --path "\$projectName\Iteration\"
    for ($j = 0; $j -lt $numberOfSprints - 1; $j++) {
        $iterationName = "$newIterationPITitle Sprint $($j + 1)"
        $startDate = $($iterationStartDate.ToString("dddd yyyy-MM-dd"))
        $endDate = $($iterationEndDate.ToString("dddd yyyy-MM-dd"))
        Write-Host "Creating iteration $iterationName $startDate - $endDate" -ForegroundColor Cyan
        
        az boards iteration project create --organization $organization --project $projectName --name "$iterationName" --start-date $startDate --finish-date $endDate --path "\$projectName\Iteration\$newIterationPITitle"

        $iterationStartDate = $iterationStartDate.AddDays(14)
        $iterationEndDate = $iterationStartDate.AddDays(11)
    }

    $iterationStartDate = $iterationStartDate.AddDays(14)
    $iterationEndDate = $iterationStartDate.AddDays(11)
    
    # Create IP sprint at the end of the PI
    az boards iteration project create --organization $organization --project $projectName --name "$newIterationPITitle IP Sprint" --start-date $iterationStartDate --finish-date $iterationEndDate --path "\$projectName\Iteration\$newIterationPITitle"
    $iterationStartDate = $iterationStartDate.AddDays(14)
    $iterationEndDate = $iterationStartDate.AddDays(11)
}

$createdIterations = az boards iteration project list --organization $organization --project $projectName --depth 4 --output json | ConvertFrom-Json

# Get all IDs of the created iterations
$iterationIds = @()
foreach ($iteration in $createdIterations.children) {
    foreach ($child in $iteration.children) {
        $iterationIds += $child.identifier
    }
}

# Get team IDs to add iterations for
$teams = az devops team list --organization $organization --project $projectName --output json | ConvertFrom-Json

# Get IDs for already existing iterations for each team in hash table
$existingIterationIds = @{}
foreach ($team in $teams) {
    $existingIterations = az boards iteration team list --organization $organization --project $projectName --team $team.id --output json | ConvertFrom-Json
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
        az boards iteration team add --organization $organization --project $projectName --team $teamId --id $iterationId
    }
}
