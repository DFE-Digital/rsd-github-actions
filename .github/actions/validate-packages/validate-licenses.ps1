Param(
    [string]$Environment,
    [string]$PolicyFilePath
)

Write-Host "Environment: $Environment"
Write-Host "License Policy File: $PolicyFilePath"

$policy = Get-Content $PolicyFilePath -Raw | ConvertFrom-Json
$allowed = @($policy.allowed)
$review  = @($policy.review)
$failReviewInEnvironments = @($policy.failReviewInEnvironments)
$reviewedPackageWhitelist = @($policy.reviewedPackageWhitelist)
$excludePackagePatterns = @()
if ($policy.PSObject.Properties.Name -contains 'excludePackagePatterns') {
    $excludePackagePatterns = @($policy.excludePackagePatterns)
}

$outputDir = Join-Path $env:RUNNER_TEMP "license-check"
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

function TryParse-Version([string] $v, [ref] [Version] $out) {
    if ([string]::IsNullOrWhiteSpace($v)) { return $false }
    $null = $v -match '(\d+(?:\.\d+){1,2})'
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

function Test-WhitelistVersionMatch {
    Param(
        [string]$PackageVersion,
        [object]$Entry
    )

    $hasVersion = $Entry.PSObject.Properties.Name -contains 'version'
    $hasVersionRegex = $Entry.PSObject.Properties.Name -contains 'versionRegex'
    $hasVersionConstraint = $Entry.PSObject.Properties.Name -contains 'versionConstraint'

    if (-not $hasVersion -and -not $hasVersionRegex -and -not $hasVersionConstraint) {
        return $true
    }

    if ($hasVersion -and -not [string]::IsNullOrWhiteSpace([string]$Entry.version)) {
        return ($PackageVersion -ieq [string]$Entry.version)
    }

    if ($hasVersionRegex) {
        $regex = [string]$Entry.versionRegex
        if (-not [string]::IsNullOrWhiteSpace($regex)) {
            return ($PackageVersion -match $regex)
        }
    }

    if ($hasVersionConstraint) {
        $constraint = [string]$Entry.versionConstraint
        if (-not [string]::IsNullOrWhiteSpace($constraint)) {
            $ruleVer = $null
            $pkgVer = $null
            $okRule = TryParse-Version $constraint ([ref]$ruleVer)
            $okPkg = TryParse-Version $PackageVersion ([ref]$pkgVer)

            if ($okRule -and $okPkg) {
                if ($constraint.StartsWith('<')) {
                    return ($pkgVer -lt $ruleVer)
                } elseif ($constraint.StartsWith('>')) {
                    return ($pkgVer -gt $ruleVer)
                }
            }
        }
    }

    return $false
}

function Test-WhitelistEntryMatch {
    Param(
        [string]$PackageName,
        [string]$PackageVersion,
        [string]$LicenseType,
        [string]$Environment,
        [object]$Entry
    )

    $hasNameRegex = $Entry.PSObject.Properties.Name -contains 'nameRegex'
    $hasNameExact = $Entry.PSObject.Properties.Name -contains 'name'

    $matchesName = $false
    if ($hasNameRegex) {
        $namePattern = [string]$Entry.nameRegex
        if (-not [string]::IsNullOrWhiteSpace($namePattern)) {
            $matchesName = ($PackageName -imatch $namePattern)
        }
    } elseif ($hasNameExact) {
        $matchesName = ($Entry.name -ieq $PackageName)
    } else {
        return $false
    }

    if (-not $matchesName) {
        return $false
    }

    $hasLicense = $Entry.PSObject.Properties.Name -contains 'license'
    if ($hasLicense -and -not [string]::IsNullOrWhiteSpace([string]$Entry.license)) {
        if ($LicenseType -ine [string]$Entry.license) {
            return $false
        }
    }

    $hasEnvironments = $Entry.PSObject.Properties.Name -contains 'environments'
    if ($hasEnvironments) {
        $entryEnvironments = @($Entry.environments)
        if ($entryEnvironments.Count -gt 0 -and ($entryEnvironments -notcontains $Environment)) {
            return $false
        }
    }

    if (-not (Test-WhitelistVersionMatch -PackageVersion $PackageVersion -Entry $Entry)) {
        return $false
    }

    return $true
}

function Get-WhitelistReason {
    Param(
        [string]$PackageName,
        [string]$PackageVersion,
        [string]$LicenseType,
        [string]$Environment,
        [object[]]$Whitelist
    )

    foreach ($entry in $Whitelist) {
        if (Test-WhitelistEntryMatch -PackageName $PackageName -PackageVersion $PackageVersion -LicenseType $LicenseType -Environment $Environment -Entry $entry) {
            $reason = [string]$entry.reason
            if ([string]::IsNullOrWhiteSpace($reason)) {
                return "Listed in reviewedPackageWhitelist."
            }
            return $reason
        }
    }

    return $null
}

function Test-PackageExcluded {
    Param(
        [string]$PackageName,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if (-not [string]::IsNullOrWhiteSpace($pattern) -and ($PackageName -match $pattern)) {
            return $true
        }
    }

    return $false
}

function Test-LooksLikeSpdxLicense {
    Param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match '^\s*https?://') { return $false }
    if ($Value -match '[\r\n]') { return $false }
    if ($Value.Length -gt 80) { return $false }
    if ($Value -match '^\s*#') { return $false }
    return $true
}

function Get-ResolvedLicenseType {
    Param([string]$License)

    if (Test-LooksLikeSpdxLicense -Value $License) {
        return $License.Trim()
    }

    return ""
}

function Resolve-LicenseScanInput {
    Param(
        [string]$OutputDir
    )

    $solutions = @(Get-ChildItem -Path . -Filter *.sln -File)
    if ($solutions.Count -eq 1) {
        return @{ Flag = '-i'; Path = $solutions[0].FullName }
    }

    if ($solutions.Count -gt 1) {
        $jsonPath = Join-Path $OutputDir "projects.json"
        $paths = @($solutions | ForEach-Object { $_.FullName })
        Set-Content -Path $jsonPath -Value (ConvertTo-Json -InputObject $paths -Compress) -Encoding utf8
        return @{ Flag = '-ji'; Path = $jsonPath }
    }

    $projects = @(Get-ChildItem -Path . -Filter *.csproj -Recurse -File)
    if ($projects.Count -eq 0) {
        Write-Host "No .sln or .csproj files found to scan for licenses."
        Exit 1
    }

    if ($projects.Count -eq 1) {
        return @{ Flag = '-i'; Path = $projects[0].FullName }
    }

    $jsonPath = Join-Path $OutputDir "projects.json"
    $paths = @($projects | ForEach-Object { $_.FullName })
    Set-Content -Path $jsonPath -Value (ConvertTo-Json -InputObject $paths -Compress) -Encoding utf8
    return @{ Flag = '-ji'; Path = $jsonPath }
}

$env:DOTNET_ROLL_FORWARD = "Major"

Write-Host "Scanning NuGet package licenses..."

$scanInput = Resolve-LicenseScanInput -OutputDir $outputDir
$licensesPath = Join-Path $outputDir "licenses.json"

$licenseToolArgs = @(
    $scanInput.Flag, $scanInput.Path
    '-t'
    '-o', 'Json'
    '-fo', $licensesPath
)

Write-Host "nuget-license input: $($scanInput.Flag) $($scanInput.Path)"

if ($excludePackagePatterns.Count -gt 0) {
    Write-Host "Excluding packages matching: $($excludePackagePatterns -join ', ')"
}

& nuget-license @licenseToolArgs
$toolExitCode = $LASTEXITCODE

if (-not (Test-Path $licensesPath)) {
    Write-Host "nuget-license failed with exit code $toolExitCode and did not create: $licensesPath"
    Exit $(if ($toolExitCode -ne 0) { $toolExitCode } else { 1 })
}

if ($toolExitCode -ne 0) {
    Write-Host "nuget-license exited with code $toolExitCode; continuing with generated license output."
}

$licenses = Get-Content $licensesPath -Raw | ConvertFrom-Json
$violations = @()
$warnings   = @()
$whitelisted = @()

foreach ($item in $licenses) {
    $packageName = [string]$item.PackageId
    $packageVersion = [string]$item.PackageVersion
    $rawLicense = [string]$item.License

    if (Test-PackageExcluded -PackageName $packageName -Patterns $excludePackagePatterns) {
        continue
    }

    $licenseType = Get-ResolvedLicenseType -License $rawLicense

    $displayLicense = if ([string]::IsNullOrWhiteSpace($licenseType)) {
        if (-not [string]::IsNullOrWhiteSpace($rawLicense)) {
            $truncated = ($rawLicense -replace '\s+', ' ').Trim()
            if ($truncated.Length -gt 60) { $truncated = $truncated.Substring(0, 57) + "..." }
            "(unresolved: $truncated)"
        } else {
            "(unknown)"
        }
    } else {
        $licenseType
    }

    $status = if ([string]::IsNullOrWhiteSpace($licenseType)) {
        "BLOCK"
    } elseif ($allowed -contains $licenseType) {
        "OK"
    } elseif ($review -contains $licenseType) {
        "REVIEW"
    } else {
        "BLOCK"
    }

    $whitelistReason = Get-WhitelistReason `
        -PackageName $packageName `
        -PackageVersion $packageVersion `
        -LicenseType $licenseType `
        -Environment $Environment `
        -Whitelist $reviewedPackageWhitelist

    if ($whitelistReason -and $status -in @("REVIEW", "BLOCK")) {
        $status = "WHITELISTED"
    }

    $row = [PSCustomObject]@{
        Package = $packageName
        Version = $packageVersion
        License = $displayLicense
        Status  = $status
        Note    = if ($status -eq "WHITELISTED") { $whitelistReason } else { "" }
    }

    switch ($status) {
        "BLOCK" { $violations += $row }
        "REVIEW" { $warnings += $row }
        "WHITELISTED" { $whitelisted += $row }
    }
}

if ($violations.Count -gt 0 -or $warnings.Count -gt 0 -or $whitelisted.Count -gt 0) {
    ($violations + $warnings + $whitelisted) | Format-Table
}

if ($violations.Count -gt 0) {
    Write-Host "Blocked licenses found ($($violations.Count) package(s))."
    Exit 1
}

if ($failReviewInEnvironments -contains $Environment -and $warnings.Count -gt 0) {
    Write-Host "Licenses requiring review found in '$Environment' ($($warnings.Count) package(s))."
    Exit 1
}

Write-Host "No disallowed licenses found for environment '$Environment'."
Exit 0
