try {
	$branchRegexPattern = "SMC-\d+"
	
	# git args
	$commitFile = $args[0] # text file with commit message
	$commitType = $args[1] # commit type: message, template, merge, squash
	$commitHash = $args[2] # SHA1 hash (optional)
	
	# git ops
	$branchName = $(git rev-parse --abbrev-ref HEAD)
	$fileContent = Get-Content -Path $commitFile
	
	# short-circuit
	if ($branchName -notmatch $branchRegexPattern) 
	{
		Exit 0
	}
	
	# get tag from branch name
	$tag = (select-string $branchRegexPattern -inputobject $branchName).Matches.groups[0].value
	
	# set commit message
	$fileContent[0] = "$($tag): " + $fileContent[0]; 
	Set-Content -Path $commitFile -Value $fileContent
}
catch 
{
	Exit 0
}
