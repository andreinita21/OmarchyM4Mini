<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# CI and security checks

Contributor PRs target `main`. Only the maintainer merges, and only changes
verified on the mini. CI builds and checks; it never publishes packages, images
or releases, and it never touches hardware.

All workflows run on standard GitHub-hosted `ubuntu-24.04` runners with a
read-only token. No secret, self-hosted runner or deployment environment is
used.

## Checks

| Workflow / job | What it covers |
| --- | --- |
| CI / Lint | `git diff --check` on the change; [shellcheck](https://www.shellcheck.net/) 0.11 at warning level on every shell script of the J773g stack (`tools/j773g*`, `tools/ci/*.sh`, `packaging/j773g/`); [ruff](https://docs.astral.sh/ruff/) on the J773g Python with the rules in [`ruff.toml`](../ruff.toml) (syntax errors, undefined names). |
| CI / Device trees | [`tools/ci/build-j773g-dtbs.sh`](../tools/ci/build-j773g-dtbs.sh): fetches the pinned GravityLinux/linux commit (device-tree paths only) and compiles the packaged `t8132-j773g.dtb` (Gravity's board file plus the PMU/poweroff and headphone nodes of `linux-gravity-m4`) and every boot-ladder rung of `tools/j773g/inner-build.sh`. Fails on a dtc error, on a missing poweroff/RTC/headphone node, or when the PKGBUILD and the ladder build pin different Gravity commits. |
| CI / Packages | [`tools/ci/check-j773g-packages.py`](../tools/ci/check-j773g-packages.py): every `packaging/j773g` PKGBUILD sources cleanly, names its package, version and `aarch64`/`any`, has one checksum per source, pins every download with a real checksum, and ships the local sources and install file it lists; stray files must at least be documented. The weekly and manual runs also download every pinned source and verify its checksum. |
| Security / Secrets | Gitleaks default rules across the history and current files; findings are redacted. |
| Security / Workflow lint | actionlint (with shellcheck for `run:` snippets) on every workflow. |
| Security / Dependency review | On PRs, blocks newly introduced moderate-or-higher advisories in supported manifests. |
| CodeQL | Python and Actions with the extended security queries; PRs, pushes and weekly. |
| Dependabot | Weekly GitHub Actions update PRs into `main`; reviewed, never merged automatically. |

Running the checks locally:

```sh
tools/ci/build-j773g-dtbs.sh              # CPP="clang -E" on macOS
python3 tools/ci/check-j773g-packages.py   # add --download to verify sources
ruff check tools/j773g
```

## Limits

CI does not build the kernel, Mesa, m1n1 or U-Boot packages (they need an
aarch64 Arch Linux ARM host; see `tools/j773g-pkg.sh`), does not boot anything
and does not run the device-tree schema checks (`CHECK_DTBS`). A green run says
the sources are consistent and the device trees compile, not that the mini
boots. Hardware behaviour is verified on the mini before a change is merged.

## Trust boundaries

Fork PRs use `pull_request`, never `pull_request_target`. Checkout credentials
are not persisted, actions are pinned by full commit SHA, downloaded tools
(shellcheck, actionlint, gitleaks) have fixed SHA-256 checksums, and ruff is
pinned by version. Only the CodeQL job may upload security results.

External contributors need maintainer approval before their workflows run.
Review the workflow, build scripts and dependencies **before** approving a run;
CODEOWNERS assigns every contribution to the maintainer, and a contributor's
own green checks are never approval.
