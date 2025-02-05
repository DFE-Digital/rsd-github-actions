Validate Packages Action
========================

What is it?
-----------

This action is a **PowerShell-based validation tool** for .NET projects. It scans your `.csproj` files to detect whether any **disallowed packages** (and/or **disallowed versions**) are present in a given environment (e.g., development, test, production). If a violation is found, the action _fails_ the job, preventing unwanted packages from being deployed.

What does it do?
----------------

*   **Checks** each `.csproj` for `<PackageReference>` entries.
*   **Compares** the package name and version against a **central policy file** (`packages-policy.json`).
*   **Enforces** rules such as “this package must be below 7.0” or “beta packages are not allowed in production.”
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
            uses: DFE-Digital/rsd-github-actions/.github/actions/validate-packages@v1.1.1
            with:
              environment: ${{ needs.set-env.outputs.environment }}
    

### Important Points

1.  `runs-on: windows-latest`  
    The script uses PowerShell features that require Windows.
2.  **environment input**  
    Lets the validator know if you’re in _development_, _test_, or _production_, so it can apply the relevant policy rules.
3.  **Blocking Violations**  
    If any disallowed package usage is found, the job fails and stops the pipeline.

* * *

2\. The Central Policy File
---------------------------

All **rules** about disallowed packages or versions are kept in a **shared** JSON file named `packages-policy.json`. The action references this file each time it runs.

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

* * *

3\. Central vs. Local Policy
----------------------------

**Current Model**: A single global policy in the shared repository hosting this action applies to all consuming services.

**Future Plans**: We plan to introduce a mechanism so each service can define additional or overriding rules in a local policy file. This will provide more fine-grained control down the road.

* * *

4\. Summary
-----------

*   **Short Description**: This action _validates_ that no unauthorized .NET packages or versions are used in your code.
*   **Usage**: Add it as a job step in your GitHub workflow on a Windows runner, specifying the environment (development, test, production).
*   **Outcome**: The build fails if it detects any package violating the policy, preventing those packages from being deployed.

With this setup, you can **enforce consistent package usage** across multiple services while retaining easy configurability for different environments.
