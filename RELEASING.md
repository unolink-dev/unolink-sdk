# Releasing

## Cutting a release

1. Bump the version in every file the `versions` job in `.github/workflows/release.yml` checks. Merge to `main` and
   wait for CI to pass.
2. Tag a commit that is on `main`, then push the tag:
   `git tag -a vX.Y.Z -m "Unolink SDK X.Y.Z" && git push origin vX.Y.Z`
3. The Release workflow checks that the tagged commit is on `main` and that every version matches the tag. It then
   publishes to npm, pub.dev and Maven Central. iOS (Swift Package Manager) is the tag itself.
4. Each publishing job skips a version that is already published, so re-running a failed release is safe.

## How the release workflow is locked down

- Every action is pinned to a full commit SHA, with the version in a comment. To update one, resolve the new tag with
  `gh api repos/OWNER/REPO/git/ref/tags/vX.Y.Z`. If that returns an annotated tag (`"type": "tag"`), dereference it
  with `gh api repos/OWNER/REPO/git/tags/<sha>`.
- npm is pinned to 11.21.1, because trusted publishing needs 11.5.1 or newer. Dependencies are installed with
  `npm ci` from `react-native/package-lock.json`.
- A tag on a commit that isn't on `main` is refused before anything is published.
- The three publishing jobs run in the `release` GitHub environment.

## One-time owner setup

Do these in order. The workflow keeps working at every step: GitHub creates the `release` environment on its first
run if it doesn't exist, and repository secrets are used until environment secrets with the same names exist.

1. **Create the `release` environment.** Settings, Environments, New environment, `release`.
   - Deployment branches and tags: **Selected branches and tags**, then add a **tag** rule `v*`. Only tag runs can
     then use the environment and its secrets.
   - Optional: Required reviewers = you. Each release then waits for your approval before anything is published.
2. **Move the Maven secrets into the environment.** In the same environment page, add the five secrets
   (`ORG_GRADLE_PROJECT_MAVENCENTRALUSERNAME`, `ORG_GRADLE_PROJECT_MAVENCENTRALPASSWORD`,
   `ORG_GRADLE_PROJECT_SIGNINGINMEMORYKEY`, `ORG_GRADLE_PROJECT_SIGNINGINMEMORYKEYID`,
   `ORG_GRADLE_PROJECT_SIGNINGINMEMORYKEYPASSWORD`), or use the CLI:
   `gh secret set ORG_GRADLE_PROJECT_SIGNINGINMEMORYKEY --env release -R unolink-dev/unolink-sdk < key.asc`
   and the same for the other four. Then delete the repository-level copies:
   `gh secret delete <NAME> -R unolink-dev/unolink-sdk`.
3. **npm trusted publisher.** On npmjs.com, open `@unolink/react-native`, then Settings, Trusted publishing. Keep the
   GitHub Actions publisher (`unolink-dev` / `unolink-sdk` / `release.yml`) and set **Environment name** to
   `release`.
4. **pub.dev automated publishing.** On pub.dev, open `unolink`, then Admin, Automated publishing. Keep GitHub Actions
   enabled for `unolink-dev/unolink-sdk`, with its current tag pattern (`v{{version}}`). Tick **Require GitHub Actions environment**
   and enter `release`.
5. **Tag ruleset.** Settings, Rules, Rulesets, New tag ruleset:
   - Name: `release tags`; Enforcement: Active.
   - Target tags: include by pattern `v*`.
   - Rules: Restrict creations, Restrict updates, Restrict deletions.
   - Bypass list: Repository admin, so only you can create, move or delete `v*` tags.
6. **Test** with the next release. A re-run of an older release runs that commit's old workflow, so it tests nothing.
   If a publish job fails on authentication after steps 3 or 4, check that the environment name is exactly `release`
   on npm and pub.dev. Clearing the environment field there brings back the old behaviour.
