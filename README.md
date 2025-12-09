# ADO PR Scraper

A PowerShell script to export completed Pull Requests from Azure DevOps repositories to CSV files.

## Authentication

The script uses Azure CLI for authentication. Make sure you're logged in:

```powershell
az login
```

## Usage

```powershell
$Repos = @(@('org', 'project', 'repo'), ... )
$CreatorId = '12345678-1234-1234-1234-123456789abc'

.\get-prs.ps1 -Repos $Repos -CreatorId $CreatorId [-Start <start-date>] [-End <end-date>]
```

## Output

The script generates one CSV file per repository containing the following columns:

- **Repository**: Repository name and ID
- **PR_Id**: Pull Request ID number
- **Title**: PR title
- **CreatedBy**: Display name of the PR creator
- **SourceBranch**: Source branch name
- **TargetBranch**: Target branch name
- **CreatedDate**: When the PR was created
- **ClosedDate**: When the PR was completed/closed
- **Description**: PR description text
- **Url**: Full URL to the PR
- **Reviewers**: Semicolon-separated list of reviewer display names

## Notes

- Only PRs with status "completed" are included
- PRs are filtered by `closedDate`, not creation date
- The script processes repositories sequentially
- Large repositories may take some time to process due to API pagination
- API pagination is totally untested