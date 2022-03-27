# where are we?
[string]$location = Get-Location

Write-Host $0

$sharedMainItems = Join-Path -Path $location "shared\*"

# go up by 2 folders
$basePath = (Split-Path -Path $location -Parent)
$basePath = (Split-Path -Path $basePath -Parent)

# get smc repos
$repos = Get-ChildItem -Path $basePath -Directory -Name "smc_*"

foreach($repo in $repos) 
{
    $repoPath = Join-Path $basePath $repo -Resolve
    $azdoPath = Join-Path -Path $repoPath ".azdo"

    $azdoShared = Join-Path -Path $azdoPath "shared"
    $azdoSharedExists = Test-Path -Path $azdoShared
    
    Invoke-Expression -Command "cd ""$azdoPath""" 
    $branch = (Invoke-Expression -Command "git rev-parse --abbrev-ref HEAD")

    if ($branch -eq "azure-pipelines") {
        if ($azdoSharedExists -eq "True") {
            Write-Host "Cleaning $azdoShared"

            $azdoGarbagePattern = Join-Path $azdoShared "*"
            Remove-Item -Path $azdoGarbagePattern

            Write-Host "Copying to $azdoShared"

            Copy-Item -Path $sharedMainItems -Destination $azdoShared -Force
        }
        else {
            Write-Host "folder $azdoShared doesn't exist."
        }
    }
}