# where are we?
[string]$location = Get-Location

# go up by 2 folders
$basePath = (Split-Path -Path $location -Parent)
$basePath = (Split-Path -Path $basePath -Parent)

# get smc repos
$repos = Get-ChildItem -Path $basePath -Directory -Name "smc_*"

foreach($repo in $repos) 
{
    $repoPath = Join-Path $basePath $repo -Resolve

    Invoke-Expression -Command "cd ""$repoPath""" 
    $branch = (Invoke-Expression -Command "git rev-parse --abbrev-ref HEAD")

    if ($branch -eq "azure-pipelines") {
            Write-Host "Commit to $azdoShared"
            Invoke-Expression "git add ."
            Invoke-Expression -Command "git commit -m ""Updated Azure Pipelines"""
            Invoke-Expression -Command "git push"
        else {
            Write-Host "not on azure pipelines branch"
        }
    }
}