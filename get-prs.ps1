<#
.SYNOPSIS
    Emits CSV files containing completed Pull Requests you created in the specified repos

.PARAMETER ServerUrl
    The URL of the Azure DevOps server.

.PARAMETER Repos
    List of the repositories to scrape in the format @(@("Org", "Project", "Repo"), ...)

.PARAMETER CreatorId
    The ID of the creator to filter Pull Requests.

.PARAMETER Start
    The start date to filter Pull Requests.

    Defaults to 6 months ago.

.PARAMETER End
    The end date to filter Pull Requests.

    Defaults to today.
#>
param(
    [Parameter(Mandatory = $true)]
    [string[][]]$Repos,
    [Parameter(Mandatory = $true)]
    [string]$CreatorId,
    [string]$Start = ((Get-Date).AddMonths(-6) -Format "yyyy-MM-dd"),
    [string]$End = ((Get-Date).AddDays(1) -Format "yyyy-MM-dd")
)

$ErrorActionPreference = "Stop"

# Date range to export PRs for
$StartDate  = (Get-Date -Date $Start)
$EndDate    = (Get-Date -Date $End)

$Pat = az account get-access-token | ConvertFrom-Json

$DateFmt      = "yyyy-MM-dd"

# ----- Helper Functions -----
function Invoke-ADO {
    param(
        [string]$Uri
    )
    $Headers = @{ Authorization = ("Bearer " + $Pat.accessToken) }
    return Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -UseBasicParsing
}

foreach ($RepoInfo in $Repos) {
    $Org         = $RepoInfo[0]
    $Project     = $RepoInfo[1]
    $Repo        = $RepoInfo[2]
    $OutFile     = "$Org-$Project-$Repo`_$($StartDate.ToString($DateFmt))`_to`_$($EndDate.ToString($DateFmt)).csv"

    Write-Host "Resolving repository ID for '$Repo' in project '$Project'..."

    # ----- Resolve repository ID -----
    $RepoListUri = "https://$Org.visualstudio.com/$Project/_apis/git/repositories?api-version=7.0"
    $AllRepos = Invoke-ADO -Uri $RepoListUri
    $RepoId = $AllRepos.value | Where-Object { $_.name -eq $Repo }
    if (-not $RepoId) { throw "Repository '$Repo' not found in project '$Project'." }
    $RepoId = $RepoId.id

    Write-Host "Repository ID: $RepoId"

    Write-Host "Fetching completed PRs for range: $($StartDate.ToString($DateFmt)) to $($EndDate.ToString($DateFmt))..."

    # ----- Pull PRs with status=completed and creator=CreatorId (page through results) -----
    $BasePrUri = "https://$Org.visualstudio.com/$Project/_apis/git/repositories/$RepoId/pullrequests?api-version=7.0" +
                "&searchCriteria.status=completed" + 
                "&searchCriteria.creatorId=$CreatorId"
    # Paging parameters
    $Top = 100
    $Skip = 0
    $AllPrs = @()

    # Write-Host "Fetching PRs from base URI: $basePrUri"

    while ($true) {
        $Uri = "$BasePrUri&`$top=$top&`$skip=$skip"
        $Batch = Invoke-ADO -Uri $Uri
        if (-not $Batch.value -or $Batch.value.Count -eq 0) { break }
        $AllPrs += $Batch.value
        $Skip += $Top
    }

    Write-Host "Fetched $($AllPrs.Count) completed PRs (unfiltered)."

    # ----- Filter to the specified date range by closedDate -----
    $InRange = $AllPrs | Where-Object {
        $_.closedDate -and
        (Get-Date $_.closedDate) -ge $StartDate -and
        (Get-Date $_.closedDate) -le $EndDate
    }

    Write-Host "After date filtering: $($InRange.Count) PRs"

    # ----- Shape rows and export CSV -----
    $Rows = $InRange | ForEach-Object {
        [PSCustomObject]@{
            Repository    = "$($_.repository.name)::$($_.repository.id)"
            PR_Id         = $_.pullRequestId
            Title         = $_.title
            CreatedBy     = $_.createdBy.displayName
            SourceBranch  = $_.sourceRefName
            TargetBranch  = $_.targetRefName
            CreatedDate   = $_.creationDate
            ClosedDate    = $_.closedDate
            Description   = $_.description
            Url           = $_.url
            Reviewers     = ($_.reviewers | ForEach-Object { $_.displayName }) -join "; "
        }
    }

    $Rows | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
}