# ADO PR Scraper

A PowerShell script to export completed Pull Requests from Azure DevOps repositories to CSV files.

You basically hand this script which ADO org/projects you've contributed to, and it will scrape every repo to find any PRs you've completed.

You'll get a CSV for each repo, and a combined CSV with every PR.

By default it filters to the last 6 months of PRs

## Usage

```powershell
$Projects = @(, @('org1', 'project1'))

# You can find this by going to any repo & filtering PRs by your account.
# Your CreatorId will be embedded in the URL.
$CreatorId = '12345678-1234-1234-1234-123456789abc'

.\get-prs.ps1 -Projects $Projects -CreatorId $CreatorId # [-Start <start-date>] [-End <end-date>]
```

## Authentication

The script uses Azure CLI for authentication. Make sure you're logged in:

```powershell
az login

# And verify everything is working
$Org = 'MyOrg'
$Project = 'MyProject'

az repos list --organization "https://$Org.visualstudio.com" --project "$Project"
```

## Notes

- Only PRs with status "completed" are included
- PRs are filtered by `closedDate`, not creation date
- The script processes repositories sequentially
- Large repositories may take some time to process due to API pagination
- API pagination is totally untested