# Pages pin republish

**Status:** ⏳ process change is local, not on `main` yet. v1.4.10's pin list is live: the Valadoc workflow was dispatched and the site now has those ten packages. The next tag still mirrors the site until this change is on `main`.

**Pointer:** `docs/bug-fix-process.md`, `.github/workflows/release.yml`, `.github/workflows/deploy-docs.yml`

## Problem

- 🔷 Publishing `release.pins` downloaded every file on `https://roojs.github.io/OLLMchat/`, then uploaded that tree again with the pin files swapped in.
- 🔷 That deploy failed, so the pin list never went live.

## Evidence

- ✔️ [Release v1.4.10](https://github.com/roojs/OLLMchat/actions/runs/42939379856) job `Stage pin page` (`130263709018`) ran `scripts/android/stage-pins-page.sh`.
- ✔️ That script `wget -r` mirrored the live Valadoc site from 01:46:42Z to 01:56:11Z, then logged `Staged 10 release pins into site`. The Pages artifact was 8 685 847 bytes.
- ✔️ Job `Publish pin page` (`130267346983`) failed before any step. Annotation: `Tag "v1.4.10" is not allowed to deploy to github-pages due to environment protection rules.`
- ✔️ Publish had already pushed `191a397` to `main` (`566f82f..191a397`). That commit's `release.pins` lists ocsqlite, ocrpc, ocmarkdown, ollamaweb, ocmarkdowngtk, ocfiles, ollmchat, ocwebkit, occoder, ollmchatgtk.
- ✔️ `https://roojs.github.io/OLLMchat/release.pins` is still `{"packages":[]}` (21 bytes, last-modified 2026-11-10 09:20:58Z). `snapshot.pins` on that site is the same empty list.
- ℹ️ `X - Publish Valadoc to GitHub Pages` already copies `release.pins` and `snapshot.pins` from the checkout into `build/valadoc` before `deploy-pages`. It runs on `main`, which the github-pages environment allows. A push made with the release token does not start that workflow.

## Root cause

- ✔️ GitHub Pages replaces the whole site from one artifact, and the github-pages environment rejects deploys from a tag. The release workflow tried to satisfy the first constraint by mirroring the live site from the tag job. The environment then rejected the deploy, after the mirror had already downloaded the documentation.

## Proposed fix

- 🔷 After the release job pushes `release.pins` to `main`, dispatch `deploy-docs.yml` on `main`. That rebuilds Valadoc and copies the pin files into the same artifact.
- 🚫 Mirror the live site from a `main` job instead. The environment would allow the deploy, and the job would still download every documentation file.
- 🚫 Point consumers at `raw.githubusercontent.com` for the pin list. The published URL is `https://roojs.github.io/OLLMchat/release.pins`.

### Release workflow

`.github/workflows/release.yml`

#### Remove

```yaml
  stage-pins:
    name: Stage pin page
    # wget the live site, upload it again
  deploy-pins:
    name: Publish pin page
    # deploy-pages from the tag
```

#### Replace with

```yaml
    permissions:
      actions: write
      contents: write
```

on the Publish job, and after `git push origin HEAD:main`, when `release.pins` is part of that commit:

```bash
gh workflow run deploy-docs.yml --ref main
```

`scripts/android/stage-pins-page.sh` goes away with those jobs.

## Attempts / changelog

- ✔️ 2026-11-11. Removed the stage and deploy pin jobs and `scripts/android/stage-pins-page.sh`. Publish dispatches the Valadoc workflow on `main` when the pin commit includes `release.pins`. `release.pins` and `snapshot.pins` are path filters on that workflow for a normal push. The release token's push does not use those filters.

## Next

- ✔️ 2026-11-11. Dispatched [X - Publish Valadoc to GitHub Pages](https://github.com/roojs/OLLMchat/actions/runs/42944870414) on `main` (`workflow_dispatch`). That run uses the workflow already on `main`, which copies `release.pins` from the checkout.
- ✔️ 2026-11-11. That run succeeded (Valadoc 1m47s, deploy 9s). `https://roojs.github.io/OLLMchat/release.pins` is 3995 bytes and lists the ten libraries. Each package URL returned HTTP 200. `https://roojs.github.io/OLLMchat/ollmchat/index.htm` returned HTTP 200 (147114 bytes). `snapshot.pins` is still the empty list.
- ⏳ 🔷 On the next version tag, after this change is on `main`, confirm Publish dispatches that workflow and does not mirror the site.
