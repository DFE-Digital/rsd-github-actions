Validate Packages Action
========================

What is it?
-----------

This action is a **PowerShell-based validation tool** for .NET projects. It scans your `.csproj` files to detect whether any **disallowed packages** (and/or **disallowed versions**) are present in a given environment (e.g., development, test, production), and checks NuGet package **licenses** against a central allow/review policy. If a violation is found, the action _fails_ the job, preventing unwanted packages from being deployed.

What does it do?
----------------

*   **Checks** each `.csproj` for `<PackageReference>` entries.
*   **Compares** the package name and version against a **central policy file** (`packages-policy.json`).
*   **Enforces** rules such as “this package must be below 7.0” or “beta packages are not allowed in production.”
*   **Scans** direct and transitive NuGet dependencies for license types using `nuget-license`.
*   **Compares** detected licenses against `licenses-policy.json` (allowed, review, and blocked).
*   **Fails** the build if any rule is violated, blocking the deployment.

* * *

1\. How to Use It
-----------------

In your GitHub Actions workflow (for example, `.github/workflows/deploy.yml`), add a job step:

    jobs:
      validate-packages:
        runs-on: windows-latest      # PowerShell script requires a Windows runner
        name: Run Package Validation
        permissions:
          contents: read
        needs: [ set-env ]           # or any prerequisite job
        steps:
          - name: Validate Packages
            uses: DFE-Digital/rsd-github-actions/.github/actions/validate-packages@v1
            with:
              environment: ${{ needs.set-env.outputs.environment }}
    

### Important Points

1.  `runs-on: windows-latest`  
    The script uses PowerShell features that require Windows.
2.  **Use `@v1` for automatic updates**  
    Reference `@v1` to always use the latest `v1.x.x` release. Update to `@v2` only when a new major version is published.
3.  **environment input**  
    Lets the validator know if you’re in _development_, _test_, or _production_, so it can apply the relevant policy rules.
4.  **Blocking Violations**  
    If any disallowed package usage or blocked license is found, the job fails and stops the pipeline.

* * *

2\. The Central Policy Files
---------------------------

All **rules** about disallowed packages or versions are kept in a **shared** JSON file named `packages-policy.json`. License allow/review rules are kept in `licenses-policy.json`. The action references both files each time it runs.

### Package policy (`packages-policy.json`)

Example:

    {
      "disallowedPackages": [
        {
          "name": "FluentAssertions",
          "rules": [
            {
              "versionConstraint": ">7.0.0",
              "environments": [ "development", "test", "production" ],
              "message": "FluentAssertions must be v7.0.0 or less."
            }
          ]
        },
        {
          "name": "DfE.CoreLibs.Testing",
          "rules": [
            {
              "versionRegex": "-prerelease",
              "environments": [ "production" ],
              "message": "PreRelease versions of DfE.CoreLibs.Testing are not allowed in production."
            }
          ]
        }
      ]
    }
    

### Explanation

*   `disallowedPackages`: An array of packages to watch for.
*   `name`: The NuGet package ID.
*   `rules`: One or more constraints:
    *   `versionConstraint` (e.g., `>7.0.0`) to disallow versions above (or below) a certain threshold.
    *   `versionRegex` (e.g., `-prerelease`) to disallow versions matching a specific pattern.
    *   `environments` determines where each rule applies (dev, test, prod, etc.).
    *   `message` is shown in the logs when a rule is violated.

### License policy (`licenses-policy.json`)

Example:

    {
      "allowed": ["MIT", "Apache-2.0", "BSD-3-Clause"],
      "review": ["MPL-2.0", "LGPL-3.0"],
      "failReviewInEnvironments": ["production"],
      "excludePackagePatterns": [
        "^Microsoft\\.",
        "^System\\.",
        "^runtime\\.",
        "^NETStandard\\."
      ],
      "reviewedPackageWhitelist": [
        {
          "name": "Some.Package",
          "version": "1.2.3",
          "license": "LGPL-3.0",
          "environments": ["production"],
          "reason": "Approved by legal review ref ABC-123."
        }
      ]
    }

#### Explanation

*   `allowed`: SPDX license identifiers that pass without warning.
*   `review`: licenses that are permitted in development/test but flagged for manual review.
*   `failReviewInEnvironments`: environments where `review` licenses cause the job to fail (typically `production`).
*   `excludePackagePatterns`: regex patterns for NuGet package IDs to skip (for example `Microsoft.*` and `System.*` framework packages). Matching packages are filtered out of the `nuget-license` results before policy evaluation.
*   Packages with an unknown, missing, or unresolved license (for example a GitHub LICENSE URL or embedded license file text instead of an SPDX id) are treated as **blocked**, unless the package is explicitly listed in `reviewedPackageWhitelist` at the matching version.
*   `reviewedPackageWhitelist`: specific package, version, and license combinations that have been manually reviewed and approved. These override `review` and `blocked` outcomes. Use this for packages whose metadata cannot be resolved to an SPDX id. A new package version will not match until it is explicitly added.

#### Whitelist entry fields

*   `name` or `nameRegex`: package ID to match (same pattern style as `packages-policy.json`).
*   `version` (recommended): exact NuGet version that was reviewed. If the resolved version changes, the package must be reviewed again and the whitelist updated.
*   `versionRegex` (optional): regex match against the package version (same style as `packages-policy.json`).
*   `versionConstraint` (optional): numeric version constraint (for example `>2.0.0` or `<3.0.0`) using the same rules as `packages-policy.json`.
*   `license` (optional): if set, only whitelists that exact license on the package. Omit to whitelist the package regardless of detected license.
*   `environments` (optional): limits the whitelist to specific environments. Omit to apply in all environments.
*   `reason` (optional): shown in the job log when a package is whitelisted.

* * *

3\. Central vs. Local Policy
----------------------------

**Current Model**: A single global policy in the shared repository hosting this action applies to all consuming services.

**Future Plans**: We plan to introduce a mechanism so each service can define additional or overriding rules in a local policy file. This will provide more fine-grained control down the road.

* * *

4\. Summary
-----------

*   **Short Description**: This action _validates_ that no unauthorized .NET packages, versions, or licenses are used in your code.
*   **Usage**: Add it as a job step in your GitHub workflow on a Windows runner, specifying the environment (development, test, production).
*   **Outcome**: The build fails if it detects any package violating the policy, preventing those packages from being deployed.

With this setup, you can **enforce consistent package usage** across multiple services while retaining easy configurability for different environments.
