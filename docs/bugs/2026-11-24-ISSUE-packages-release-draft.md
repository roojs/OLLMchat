# Packages GitHub Release is left as a draft

**Status:** ✔️

### User decisions required

- 💩 Run `./scripts/release.sh` once so `v1.4.17-packages` is pushed to git.roojs.com. The release already building uses the old workflow and will leave the packages release as a draft unless that tag is on the mirror source.

### User reported

- 🔷 The release process creates a release, then the package release ends up as a draft.
- 🔷 A draft is not valid. The packages release should always be published on GitHub.

### Success scenario

- `scripts/release.sh` pushes `vX.Y.Z` and `vX.Y.Z-packages` to git.roojs.com in one tag push.
- Publish creates the packages GitHub Release only when `vX.Y.Z-packages` is already on GitHub.
- After the next mirror sync, that release stays published (`draft` false) and the tag still exists.
- `v1.4.17-packages` is on git.roojs.com before the mirror can delete a GitHub-only copy.

### Current behavior

- What you said
  - The package release is created and then ends up as a draft.
- Observable outcome
  - `v1.4.14-packages` is the only packages release on GitHub.
  - It is a draft. Its page is `releases/tag/untagged-385cd20ab910c23605ee`.
  - `published_at` is `2026-11-17T09:19:37Z`, the same time as the `ReleaseEvent published` for that tag.
  - `v1.4.16` and `v1.4.15` are published. There is no `v1.4.16-packages` or `v1.4.15-packages` release.
  - Publish for `v1.4.16` and `v1.4.17` printed `https://github.com/roojs/OLLMchat/releases/tag/v1.4.16-packages` and the `v1.4.17-packages` URL, so those releases were published at the end of the job.
  - No `v*-packages` tag exists on GitHub or on `https://git.roojs.com/OLLMchat`.
  - Version tags `v1.4.1` through `v1.4.17` exist on both.
  - Delete events for `v1.4.14-packages` and `v1.4.15-packages` are actor `roojs`, not `github-actions[bot]`.
  - The `v1.4.15-packages` delete is the same second as a `main` push by `roojs`.

### Codebase observed behavior

- [`scripts/release.sh`](../../scripts/release.sh) pushes the annotated version tag to `origin` (`https://git.roojs.com/OLLMchat`). It does not create `vX.Y.Z-packages`.
- [`scripts/release.sh`](../../scripts/release.sh) `--retry` deletes both the version tag and `vX.Y.Z-packages` on origin, then pushes only the version tag.
- [`.github/workflows/release.yml`](../../.github/workflows/release.yml) pushes `vX.Y.Z-packages` to GitHub during Publish when the tag is missing, then runs `gh release create`.
- That workflow ignores `v*-packages`, so the tag push does not start another build.
- [`/home/alan/gitlive/argusrm/scripts/release.sh`](/home/alan/gitlive/argusrm/scripts/release.sh) states that the GitHub mirror starts the release workflow after the push to origin.

### Debugging

#### Current debug output

- `v1.4.16` Publish job `137092802864`, run `44983878105`
  - `* [new tag] b39e0a7ab1d8c82c184e1c97ea392cc04b126dbb -> v1.4.16-packages`
  - `https://github.com/roojs/OLLMchat/releases/tag/v1.4.16-packages`
- `v1.4.17` Publish job `137542987730`, run `45128432365`
  - `* [new tag] 14e2325c42dbbcd92e3eb001d93a50e0111da6b9 -> v1.4.17-packages`
  - `https://github.com/roojs/OLLMchat/releases/tag/v1.4.17-packages`
- GitHub `GET /repos/roojs/OLLMchat/releases` on 2026-11-24
  - One packages release: `{"draft":true,"tag":"v1.4.14-packages","published":"2026-11-17T09:19:37Z"}`
- `git ls-remote --tags origin 'refs/tags/v1.4.*-packages'`
  - empty

#### Debug code added (remove when complete)

None.

### Proposed fix

Root cause: Publish creates `vX.Y.Z-packages` only on GitHub. The git.roojs.com mirror copies tags the other way and deletes GitHub tags that are not on the source. Deleting the git tag turns that GitHub Release back into a draft. The version tag stays published because `scripts/release.sh` pushes it to git.roojs.com.

### ✔️ Phase 1 — push the packages tag with the version tag

[`scripts/release.sh`](../../scripts/release.sh). Same commit as `vX.Y.Z`. One `git push` sends both tags so the mirror copies them together. If the version tag is already on origin and the packages tag is not, push only the missing packages tag.

#### Remove

```bash
if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  echo "Tag ${tag} already exists locally — nothing to do."
  echo "Re-run with --retry to delete it and retag HEAD." >&2
  exit 0
fi

if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
  echo "Tag ${tag} already exists on origin — nothing to do."
  echo "Re-run with --retry to delete it and retag HEAD." >&2
  exit 0
fi

echo "Creating annotated tag ${tag}..."
git tag -a "${tag}" -m "${tag}"

branch="$(git rev-parse --abbrev-ref HEAD)"
echo "Pushing ${branch} and ${tag} to origin..."
git push -u origin "${branch}"
git push origin "${tag}"
```

#### Replace with

```bash
pkg="${tag}-packages"

# A packages tag that exists only on GitHub is deleted by the git.roojs.com
# mirror. GitHub then turns that release back into a draft.
if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null \
  || git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
  if git ls-remote --exit-code --tags origin "refs/tags/${pkg}" >/dev/null 2>&1; then
    echo "Tag ${tag} already exists — nothing to do."
    echo "Re-run with --retry to delete it and retag HEAD." >&2
    exit 0
  fi
  echo "Pushing missing ${pkg} at the same commit as ${tag}."
  if git rev-parse -q --verify "refs/tags/${pkg}" >/dev/null; then
    git tag -d "${pkg}"
  fi
  git tag "${pkg}" "${tag}^{}"
  git push origin "${pkg}"
  echo "Pushed ${pkg}. The GitHub mirror will keep the packages release published."
  exit 0
fi

echo "Creating annotated tag ${tag}..."
git tag -a "${tag}" -m "${tag}"
git tag "${pkg}" "${tag}^{}"

branch="$(git rev-parse --abbrev-ref HEAD)"
echo "Pushing ${branch}, ${tag}, and ${pkg} to origin..."
git push -u origin "${branch}"
git push origin "${tag}" "${pkg}"
```

### ✔️ Phase 2 — do not create the packages tag from GitHub Actions

[`.github/workflows/release.yml`](../../.github/workflows/release.yml). Publish fails when `vX.Y.Z-packages` is not already on GitHub. It must not `git push` that tag itself.

#### Remove

```bash
          pkg_tag="${GITHUB_REF_NAME}-packages"
          # A release whose git tag is missing stays an untagged draft.
          # Push the tag at this commit before creating the release.
          if ! git ls-remote --exit-code --tags origin "refs/tags/${pkg_tag}" >/dev/null; then
            git push origin "${GITHUB_SHA}:refs/tags/${pkg_tag}"
          fi
```

#### Replace with

```bash
          pkg_tag="${GITHUB_REF_NAME}-packages"
          # scripts/release.sh pushes this tag to git.roojs.com with the
          # version tag. The mirror copies it here. Creating it only on
          # GitHub gets it deleted on the next mirror sync, and GitHub
          # turns the release back into a draft.
          if ! git ls-remote --exit-code --tags origin "refs/tags/${pkg_tag}" >/dev/null; then
            echo "missing git tag ${pkg_tag}." >&2
            echo "scripts/release.sh has to push that tag to git.roojs.com with the version tag." >&2
            exit 1
          fi
```

Workflow header in the same file.

#### Remove

```yaml
# Publish pushes the packages git tag itself. This workflow ignores
# v*-packages, so that push does not start another build. gh will not
# publish a release whose git tag does not already exist.
```

#### Replace with

```yaml
# scripts/release.sh pushes vX.Y.Z-packages to git.roojs.com with the
# version tag. The mirror copies it here. This workflow ignores
# v*-packages, so that push does not start another build. A packages
# tag that exists only on GitHub is deleted on the next mirror sync,
# and GitHub turns the release back into a draft.
```

### ✔️ Phase 3 — docs

[`docs/creating-releases.md`](../creating-releases.md). The packages tag is pushed to git.roojs.com. A GitHub-only tag is deleted by the mirror.

#### Remove

```markdown
6. On a tag push, publishes **two** GitHub Releases only after Android, Debian, RPM, Windows, and AppImage have all succeeded. An AppImage failure skips Publish. Publish first pushes the git tag `${tag}-packages` at the same commit (this workflow ignores `v*-packages`, so that push does not rebuild). Without that git tag, GitHub leaves the release as an untagged draft. `.deb`, `.rpm`, `.pixie`, Windows library archives, and the AppImage go on `${tag}-packages` (not marked Latest). The Windows installer and the APKs go on the version tag, so that tag appears above packages on the Releases page. Publish deletes a leftover draft for either tag before creating it, and refuses to publish when the APK or either AppImage is missing.
```

#### Replace with

```markdown
6. On a tag push, publishes **two** GitHub Releases only after Android, Debian, RPM, Windows, and AppImage have all succeeded. An AppImage failure skips Publish. `scripts/release.sh` pushes the git tag `${tag}-packages` to git.roojs.com with the version tag. The GitHub mirror copies it. This workflow ignores `v*-packages`, so that push does not rebuild. Publish refuses to create the packages release when that tag is not already on GitHub. A packages tag created only on GitHub is deleted on the next mirror sync, and GitHub turns the release back into a draft. `.deb`, `.rpm`, `.pixie`, Windows library archives, and the AppImage go on `${tag}-packages` (not marked Latest). The Windows installer and the APKs go on the version tag, so that tag appears above packages on the Releases page. Publish deletes a leftover draft for either tag before creating it, and refuses to publish when the APK or either AppImage is missing.
```

#### Remove

```markdown
   That deletes the local and origin version tag **and** the matching `v*-packages` tag, then tags HEAD and pushes again. Existing GitHub Releases for those tags are updated (`gh release upload --clobber`), not recreated.
```

#### Replace with

```markdown
   That deletes the local and origin version tag **and** the matching `v*-packages` tag, then tags HEAD and pushes both tags again. Existing GitHub Releases for those tags are updated (`gh release upload --clobber`), not recreated. Pushing only the version tag leaves the packages release as a draft after the next mirror sync.
```

### LLM

- ℹ️ GitHub `mirror_url` for `roojs/OLLMchat` is null. This repo is the mirror destination. `origin` in this checkout is `https://git.roojs.com/OLLMchat`.
- ℹ️ `gh release create` with assets creates a draft, uploads, then PATCHes `draft: false`. The printed URL used the tag name, so Publish had already published the release. The draft state is later, when the tag is deleted.
- 🚫 Leaving the Actions `git push` of `vX.Y.Z-packages` in place recreates the tag the mirror deletes.
- ℹ️ `v1.4.17` Actions run `45348982046` was still building when this was written. That run checks out the old `release.yml` from the tag, so it will still push the packages tag only to GitHub.
- 🚫 Agents must not run `scripts/release.sh` or push the tag themselves.
- ✔️ Applied in `scripts/release.sh`, `.github/workflows/release.yml`, and `docs/creating-releases.md`. Header comment and `--help` say both tags are pushed.
- ℹ️ `scripts/release.sh` still refuses a dirty tree, so it will not push `v1.4.17-packages` until these edits are committed. The tag command below does not need a clean tree.
