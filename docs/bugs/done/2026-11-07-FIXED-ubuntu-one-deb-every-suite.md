# One Ubuntu .deb is published into plucky, questing, and resolute

**Status:** ✅ 2026-11-07. User closed it. Plucky, questing, and resolute each have their own job in `.github/workflows/x-debian.yml`. The next release publishes `+plucky` and `+questing`.

## Problem

- 🔷 `apt install libocrpc-dev` on this machine (Ubuntu 25.04, plucky) fails.
- 🔷 `libocrpc1` 1.4.6-1 depends on `libgirepository-2.0-0 (>= 2.85.1)`. Plucky has `2.84.1-1ubuntu0.2`.
- 🔷 The Ubuntu package build is one release (26.04). It has to be one build per Ubuntu suite.

## Evidence

- ✔️ This host: `VERSION_CODENAME=plucky`, `libc6` `2.41-6ubuntu1.2`, GJS `1.82.1-1`. `ldd /usr/bin/gjs` is `libgirepository-1.0.so.1`.
- ✔️ Roojs indexes, same file `pool/main/o/ollmchat/libocrpc1_1.4.6-1_amd64.deb` SHA256 `3706217eaacb4f458d5dae1f4edd554110a65fdeffa2a0ff7cc11cd2f737d5d5`, in plucky, questing, and resolute. Trixie is a different file, `1.4.6-1+trixie`, and depends on `libgirepository-1.0-1`.
- ✔️ That shared Ubuntu binary also depends on `libc6 (>= 2.43)` (`libocvector2-1`, `ollmchat-remote-only`) and `libwebkitgtk-6.0-webdriver4 (>= 2.52.6-0ubuntu0.26.04.1+webdriver6)` (`libocwebkit1`).
- ✔️ Ubuntu `libgirepository-2.0-0`: plucky `2.84.1`, questing `2.86.0`, resolute `2.88.0`. Questing `libgjs0` depends on `libgirepository-2.0-0 (>= 2.85.1)`. Plucky GJS does not.
- ✔️ libc: plucky `2.41`, questing `2.42`, resolute `2.43` (`docs/plans` in the repos project).
- ℹ️ Repos ingest (`scripts/lib/deb-pkg-name.sh` `deb_file_suites_json` on `roojs/repos` `a9a6a19`) sends `+<codename>` to that suite only, and keeps the unsuffixed `.deb` off any suite that has its own `+` build. `+plucky` and `+questing` need no publisher change. The plain revision then stays on resolute.

## Root cause

- ✔️ `.github/workflows/x-debian.yml` builds one Ubuntu binary on `ubuntu:26.04`. The repos publisher puts that unsuffixed file in every Ubuntu suite. `dpkg-shlibdeps` recorded Resolute's libraries. Plucky cannot install them, and neither can questing (`libc6` 2.42, WebDriver `2.52.3`).

## Proposed fix

- 🔷 Three Ubuntu jobs, same steps as today's `ubuntu:26.04` job. Trixie stays its own job.
- 🔷 Plucky: `ubuntu:25.04`, `ROOJS_APT_SUITE=plucky`, `libgirepository1.0-dev`, no `>= 2.86` gate. Version `+plucky`. WebDriver stays on. Meson still links girepository 1.0 because `girepository-2.0 >= 2.86` is not there.
- 🔷 Questing: `ubuntu:25.10`, `ROOJS_APT_SUITE=questing`, `libgirepository-2.0-dev`, `pkg-config --atleast-version=2.86 girepository-2.0`. Version `+questing`.
- 🔷 Resolute: `ubuntu:26.04`, plain revision, same 2.0 gate as now. Artifact name stays `ollmchat-debian`.
- 🚫 Do not put the Trixie `.deb` in plucky. That build has WebDriver disabled, and `+trixie` is the Debian suite only.
- 🚫 Do not keep sharing the Resolute binary with questing. `libc6 (>= 2.43)` and the 26.04 WebDriver dependency are not installable on 25.10.

## Attempts / changelog

- ✔️ Read the four suite `Packages` files and this host's girepository / GJS / libc.
- ✔️ `.github/workflows/x-debian.yml` Ubuntu job is a three-row matrix (`+plucky`, `+questing`, plain resolute).
- ✅ 2026-11-07. User closed this. Trixie WebDriver stays open in `docs/bugs/2026-11-06-trixie-webkit-webdriver.md`.

## Next

- ✅ Closed. The three Ubuntu jobs are in the tree. Publishing them is the next release, not this bug.
