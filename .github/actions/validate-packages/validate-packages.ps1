# File: .github/scripts/validate-packages.ps1
Param(
    [string]$Environment, # "development", "test", or "production"
    [string]$PolicyFilePath
)

Write-Host "Environment: $Environment"
Write-Host "Policy File: $PolicyFilePath"

# Read the policy JSON
$policyJson = Get-Content $PolicyFilePath -Raw | ConvertFrom-Json

$disallowedPackages = $policyJson.disallowedPackages

# Gather all .csproj files
$csprojFiles = Get-ChildItem -Path . -Filter *.csproj -Recurse

$errors = @()

ForEach ($file in $csprojFiles) {
    Write-Host "Scanning $($file.FullName)..."

    # Load XML from the .csproj
    [xml]$xmlContent = Get-Content $file.FullName

    # Select all PackageReference
    $packageRefs = $xmlContent.Project.ItemGroup.PackageReference

    ForEach ($ref in $packageRefs) {
        $packageName = $ref.Include
        $packageVersion = $ref.Version

        if (-not $packageVersion) {
            # TODO: Some csproj might define versions in Directory.Packages.props, implement a solution for centralized packages
            Continue
        }

        # Now check against each rule
        ForEach ($packagePolicy in $disallowedPackages) {
            if ($packagePolicy.name -eq $packageName) {

                # This package has rules we need to check
                ForEach ($rule in $packagePolicy.rules) {

                        # Does this rule apply to our envionment?
                        if ($rule.environments -contains $Environment) {

                            # Check versionConstraint
                            if ($rule.PSObject.Properties.Name -contains 'versionConstraint') {
                                $constraint = $rule.versionConstraint

                                $minVersionMatch = $constraint -match "(\d+\.?\d*\.?\d*)"

                                if ($constraint.StartsWith("<")) {
                                    $ruleVersion = $Matches[1]

                                    $parsedRuleVersion = [Version]$ruleVersion
                                    $parsedPackageVersion = [Version]$packageVersion
                                    
                                    if ($parsedPackageVersion -lt $parsedRuleVersion) {
                                        $errors += "$($file.FullName): Package $($packageName) version $($packageVersion) violates rule: $($rule.message)"
                                    }
                                } elseif ($constraint.StartsWith(">")) {
                                    $ruleVersion = $Matches[1]

                                    $parsedRuleVersion = [Version]$ruleVersion
                                    $parsedPackageVersion = [Version]$packageVersion
                                    
                                    if ($parsedPackageVersion -gt $parsedRuleVersion) {
                                        $errors += "$($file.FullName): Package $($packageName) version $($packageVersion) violates rule: $($rule.message)"
                                    }
                                }

                            }
                        }

                        # Check versionRegex, 
                        if ($rule.PSObject.Properties.Name -contains 'versionRegex') {
                            $regex = $rule.versionRegex
                            if ($packageVersion -match $regex) {
                                $errors += "$($file.FullName): Package $($packageName) version $($packageVersion) violates rule: $($rule.message)"
                            }
                        }
                    }
                }
            }
        }
}


# Fail if we found any violations
if ($errors.Count -gt 0) {
    Write-Host "Errors found:"
    $errors | ForEach-Object { Write-Host $_ }
    Exit 1
} else {
    Write-Host "No disallowed packages found for environment '$Environment'."
    Exit 0
}
