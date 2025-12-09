<#
.SYNOPSIS
    Emits CSV files containing completed Pull Requests you created in the specified repos

.PARAMETER ServerUrl
    The URL of the Azure DevOps server.

.PARAMETER Projects
    List of the projects to scrape in the format @(@("Org", "Project"), ...)

.PARAMETER CreatorId
    The CreatorId used to filter Pull Requests.

.PARAMETER Start
    The start date to filter Pull Requests.

    Defaults to 6 months ago.

.PARAMETER End
    The end date to filter Pull Requests.

    Defaults to today.
#>
param(
    [Parameter(Mandatory = $true)]
    [string[][]]$Projects,
    [Parameter(Mandatory = $true)]
    [string]$CreatorId,
    [DateTime]$Start = (Get-Date).AddMonths(-6),
    [DateTime]$End = (Get-Date).AddDays(1) # avoid any time zone or other issues...
)

$ErrorActionPreference = "Stop"

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

$CombinedOutFile = "PRs_Combined_$($Start.ToString($DateFmt))_to_$($End.ToString($DateFmt)).csv"
if (Test-Path $CombinedOutFile) {
    Remove-Item $CombinedOutFile
}

foreach ($ProjectInfo in $Projects) {
    $Org         = $ProjectInfo[0]
    $Project     = $ProjectInfo[1]
    write-Host "Processing project '$Project' in organization '$Org'..."
    $Repos = (az repos list --organization "https://$Org.visualstudio.com" --project "$Project") -join "`n" | ConvertFrom-Json
    foreach ($Repo in $Repos) {
        $RepoName = $Repo.name
        $RepoId = $Repo.id
        $OutFile     = "${Org}_${Project}_${RepoName}_$($Start.ToString($DateFmt))_to_$($End.ToString($DateFmt)).csv"

        Write-Host "Resolving repository ID for '$RepoName' in project '$Project'..."

        Write-Host "Fetching completed PRs for range: $($Start.ToString($DateFmt)) to $($End.ToString($DateFmt))..."
        # ----- Pull PRs with status=completed and creator=CreatorId (page through results) -----
        $BasePrUri = "https://$Org.visualstudio.com/$Project/_apis/git/repositories/$RepoId/pullrequests?api-version=7.0" +
                    "&searchCriteria.status=completed" + 
                    "&searchCriteria.creatorId=$CreatorId"
        # Paging parameters
        $Top = 100
        $Skip = 0
        $AllPrs = @()

        # Write-Host "Fetching PRs from base URI: $basePrUri"

        try {
            while ($true) {
                $Uri = "$BasePrUri&`$top=$top&`$skip=$skip"
                $Batch = Invoke-ADO -Uri $Uri
                if (-not $Batch.value -or $Batch.value.Count -eq 0) { break }
                $AllPrs += $Batch.value
                $Skip += $Top
            }
        } catch {
            Write-Host "Error fetching PRs: $_"
            continue
        }

        Write-Host "Fetched $($AllPrs.Count) completed PRs (unfiltered)."

        # ----- Filter to the specified date range by closedDate -----
        $InRange = $AllPrs | Where-Object {
            $_.closedDate -and
            (Get-Date $_.closedDate) -ge $Start -and
            (Get-Date $_.closedDate) -le $End
        }

        Write-Host "After date filtering: $($InRange.Count) PRs"

        if ($InRange.Count -eq 0) {
            Write-Host "No PRs found in the specified date range. Skipping CSV export."
            continue
        }

        # ----- Shape rows and export CSV -----
        $Rows = $InRange | ForEach-Object {
            [PSCustomObject]@{
                Organization  = $Org
                Project       = $Project
                Repository    = $_.repository.name
                # PR_Id         = $_.pullRequestId
                Title         = $_.title
                # CreatedBy     = $_.createdBy.displayName
                # SourceBranch  = $_.sourceRefName
                # TargetBranch  = $_.targetRefName
                CreatedDate   = $_.creationDate
                ClosedDate    = $_.closedDate
                Description   = $_.description
                # Url           = $_.url
                # Reviewers     = ($_.reviewers | ForEach-Object { $_.displayName }) -join "; "
            }
        }

        $Rows | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
        $Rows | Export-Csv -Append -Path $CombinedOutFile -NoTypeInformation -Encoding UTF8 
    }
}