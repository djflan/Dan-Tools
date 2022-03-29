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

    if ($branch -eq "azure-pipelines") 
	{
        write-host "[$repo]`r`n`ttrying commit and push."
        invoke-expression "git add ."
        invoke-expression -command "git commit -m ""updated azure pipelines"""
        invoke-expression -command "git push"
	}		
    else
	{
        Write-Host "[$repo]`r`n`tNot on azure pipelines branch."
    }
}

Invoke-Expression -Command "cd ""$location"""