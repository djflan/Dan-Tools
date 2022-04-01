# Class for NuGet-Generated projects
class NuGetProject {
    # [string] $OwnerRepository
    # [string] $ProjectFile
    [string] $PackageId
    [string] $PackageVersion
}

# All nuget projects
$nugetProjects = [System.Collections.ArrayList]::new()

# should check for existing manifest and add to update a single one

# Get all csproj files recursively
$projects = (Get-ChildItem -Path "*.csproj" -Recurse) #"test/*.csproj" #"*.csproj" -Recurse 

ForEach ($csProject in $projects) {
    $projectXml = [xml] (Get-Content -Path $csProject)
    $sdkAttribute = (Select-Xml -Xml $projectXml -XPath "/Project/@Sdk") ?? ""
    $isSdkProject = ($sdkAttribute).ToString() -eq "Microsoft.NET.Sdk"
    
    if ($isSdkProject) {
        # Get Sdk project information
        $isPackableNodes = (Select-Xml $projectXml -XPath "//PropertyGroup/IsPackable") 
        $isPackableNode = if ($isPackableNodes.Length -eq 1) { $isPackableNodes[0]} else { "False"}

        $versionNode = (Select-Xml $projectXml -XPath "/Project/PropertyGroup/Version") ?? ""
        $idNode = (Select-Xml $projectXml -XPath "/Project/PropertyGroup/PackageId") ?? ""

        #Write-Host $versionNode

        if ($isPackableNode.ToString() -eq "True") { 

            $nugetProject = [NuGetProject]::new()
            # $nugetProject.OwnerRepository = "some repo"
            # $nugetProject.ProjectFile = $csProject
            $nugetProject.PackageId = $idNode
            $nugetProject.PackageVersion = $versionNode

            [void]$nugetProjects.Add($nugetProject)
        }
    }
}

$nugetProjects | Out-File "nuget.manifest" -Append

