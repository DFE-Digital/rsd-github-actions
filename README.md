# rsd-github-actions

Central repository for shared GitHub Actions and workflows used across RSD projects.

## Consuming actions

Reference actions with the **floating major version tag** so downstream repos automatically pick up new `v1.x.x` releases:

```yaml
- name: Validate Packages
  uses: DFE-Digital/rsd-github-actions/.github/actions/validate-packages@v1
  with:
    environment: ${{ needs.set-env.outputs.environment }}
```

GitHub Actions does not support wildcard refs such as `@v1.*`. The `@v1` tag is maintained automatically and always points at the latest `v1.x.x` release.

When a **major version** changes (for example `v2.0.0`), downstream repos must update their reference manually (for example from `@v1` to `@v2`).

## Releasing a new version

1. Merge your changes to `main` via pull request (see [Governance](#governance) below).
2. Create and push an immutable semver tag:

   ```bash
   git tag v1.2.0
   git push origin v1.2.0
   ```

3. The [Release workflow](.github/workflows/release.yml) will:
   - Validate the tag format (`vMAJOR.MINOR.PATCH`)
   - Move the floating `v1` tag to the new release (for all `v1.x.x` tags)
   - Publish a GitHub Release with generated release notes

### First-time bootstrap

If the floating `v1` tag does not exist yet, push any `v1.x.x` tag (or re-run the Release workflow for an existing tag) to create it.

## Governance

Changes to `main` are protected by a repository ruleset that requires:

- Pull requests (no direct pushes to `main`)
- At least one approving review
- Approval from a [code owner](.github/CODEOWNERS)

The ruleset is defined in [`.github/rulesets/main-protection.json`](.github/rulesets/main-protection.json) and applied by the [Apply Repository Ruleset workflow](.github/workflows/apply-repository-ruleset.yml).

### Setup after merging these changes

1. **Update CODEOWNERS** — edit [`.github/CODEOWNERS`](.github/CODEOWNERS) and replace `@DFE-Digital/rsd-admins` with the GitHub team that owns this repository.
2. **Apply the ruleset** — a repository admin runs **Actions → Apply Repository Ruleset → Run workflow** once (it also runs automatically when ruleset files change on `main`).
3. **Allow workflow administration permissions** — in **Settings → Actions → General → Workflow permissions**, ensure workflows can use `administration: write` (required for the ruleset workflow).

If the ruleset workflow cannot obtain sufficient permissions, a repository admin can create the same ruleset manually in **Settings → Rules → Rulesets** using the JSON file as a reference.

## Actions

| Action | Description |
|--------|-------------|
| [validate-packages](.github/actions/validate-packages/) | Validates .NET package references against a central policy |
