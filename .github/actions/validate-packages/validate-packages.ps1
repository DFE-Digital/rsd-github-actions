# File: .github/actions/validate-packages.ps1
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

function TryParse-Version([string] $v, [ref] [Version] $out) {
    # Accept only pure numeric versions for [Version]; ignore things like -beta.
    # Extract the first N.N or N.N.N run for safe parsing.
    if ([string]::IsNullOrWhiteSpace($v)) { return $false }
    $null = $v -match '(\d+(?:\.\d+){1,2})'  # 1.2 or 1.2.3
    if ($Matches -and $Matches[1]) {
        try {
            $out.Value = [Version]$Matches[1]
            return $true
        } catch {
            return $false
        }
    }
    return $false
}

ForEach ($file in $csprojFiles) {
    Write-Host "Scanning $($file.FullName)..."

    # Load XML from the .csproj
    [xml]$xmlContent = Get-Content $file.FullName

    # Select all PackageReference (guard for multiple ItemGroups)
    $packageRefs = @()
    $xmlContent.Project.ItemGroup | ForEach-Object {
        if ($_.PackageReference) { $packageRefs += $_.PackageReference }
    }

    ForEach ($ref in $packageRefs) {
        $packageName    = [string]$ref.Include
        # Do NOT skip when Version is missing; rules like versionRegex: ".*" should still apply.
        $packageVersion = [string]$ref.Version  # becomes "" when missing

        if ([string]::IsNullOrWhiteSpace($packageName)) {
            continue
        }

        # Evaluate against each policy block
        ForEach ($packagePolicy in $disallowedPackages) {

            # Name matching: prefer nameRegex (case-insensitive), otherwise exact name (case-insensitive)
            $matchesName = $false
            $hasNameRegex = $packagePolicy.PSObject.Properties.Name -contains 'nameRegex'
            $hasNameExact = $packagePolicy.PSObject.Properties.Name -contains 'name'

            if ($hasNameRegex) {
                $namePattern = [string]$packagePolicy.nameRegex
                if (-not [string]::IsNullOrWhiteSpace($namePattern)) {
                    # -imatch is case-insensitive
                    $matchesName = ($packageName -imatch $namePattern)
                }
            } elseif ($hasNameExact) {
                $matchesName = ($packagePolicy.name -ieq $packageName)
            } else {
                # If neither name nor nameRegex is present, skip this policy
                continue
            }

            if (-not $matchesName) {
                continue
            }

            # This package matches the policy "target"; check rules
            ForEach ($rule in $packagePolicy.rules) {
                if (-not ($rule.environments -contains $Environment)) {
                    continue
                }

                $msg = [string]$rule.message
                if ([string]::IsNullOrWhiteSpace($msg)) {
                    $msg = "Package violates policy."
                }

                $hasVersionConstraint = $rule.PSObject.Properties.Name -contains 'versionConstraint'
                $hasVersionRegex      = $rule.PSObject.Properties.Name -contains 'versionRegex'
                $hasDisallowAll       = $rule.PSObject.Properties.Name -contains 'disallowAllVersions'
                $disallowAll          = $hasDisallowAll -and [bool]$rule.disallowAllVersions

                # Blanket disallow (if we ever choose to use it in policy)
                if ($disallowAll) {
                    $errors += "$($file.FullName): Package $packageName version '$packageVersion' violates rule: $msg"
                    continue
                }

                # Version constraint (e.g., "<7.0.0" or ">7.0.0")
                if ($hasVersionConstraint) {
                    $constraint = [string]$rule.versionConstraint
                    if (-not [string]::IsNullOrWhiteSpace($constraint)) {

                        # Parse the numeric portion of the rule version
                        $ruleVer = $null
                        $okRule = TryParse-Version $constraint ([ref]$ruleVer)

                        # Parse the package version
                        $pkgVer = $null
                        $okPkg = TryParse-Version $packageVersion ([ref]$pkgVer)

                        if ($okRule -and $okPkg) {
                            if ($constraint.StartsWith('<')) {
                                # Disallow any package version that is LESS than the rule version
                                if ($pkgVer -lt $ruleVer) {
                                    $errors += "$($file.FullName): Package $packageName version '$packageVersion' violates rule: $msg"
                                }
                            } elseif ($constraint.StartsWith('>')) {
                                # Disallow any package version that is GREATER than the rule version
                                if ($pkgVer -gt $ruleVer) {
                                    $errors += "$($file.FullName): Package $packageName version '$packageVersion' violates rule: $msg"
                                }
                            }
                        } else {
                            # If we couldn't parse versions, we can't safely evaluate a numeric constraint.
                            # For now, we skip.
                        }
                    }
                }

                # Version regex (works even if version is empty; ".*" will match empty)
                if ($hasVersionRegex) {
                    $regex = [string]$rule.versionRegex
                    if (-not [string]::IsNullOrWhiteSpace($regex)) {
                        if ($packageVersion -match $regex) {
                            $errors += "$($file.FullName): Package $packageName version '$packageVersion' violates rule: $msg"
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
