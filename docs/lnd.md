# Updating LND

Read [shared conventions](conventions.md). Commands below run in
`submodules/lnd` unless explicitly shown from the parent. Replace placeholders;
they are not literal commands to paste unchanged.

## 1. Select upstream and inventory our overlay

From this repository root, select upstream using the
[shared selection rules](conventions.md#select-the-upstream-release):

```bash
UPSTREAM_TAG=$(bash scripts/check.sh latest lnd)
VERSION=$UPSTREAM_TAG
```

Continue in `submodules/lnd` in the same shell.

Complete the [shared preparation checks](conventions.md#boundaries-and-preparation).
Configure `upstream` if absent (verify the URL if it already exists):

```bash
git remote add upstream https://github.com/lightningnetwork/lnd.git
git fetch origin
git fetch --no-tags upstream "refs/tags/$UPSTREAM_TAG:refs/tags/$UPSTREAM_TAG"
git ls-remote upstream "refs/tags/$UPSTREAM_TAG" "refs/tags/$UPSTREAM_TAG^{}"
```

Read the selected release notes with
`gh release view "$UPSTREAM_TAG" --repo lightningnetwork/lnd` to assess
compatibility. Fetch the previous upstream tag too when needed.
Record the [previous-release variables](conventions.md#naming-and-patch-review)
from verified history. From the parent, inspect the previous overlay:

```bash
bash scripts/check.sh patches lnd "$PREVIOUS_UPSTREAM_TAG" "$PREVIOUS_IMAGE_TAG"
```

Identify the current consolidated BTCPay overlay and inspect open/merged PRs for
later fixes as part of the shared patch inventory. Determine which fixes are
already consolidated rather than replaying a historical commit list. `master`
may lag the latest release branch.

Create the version branch from the verified upstream commit:

```bash
git switch -c "lnd/$UPSTREAM_TAG" "$UPSTREAM_TAG"
```

Cherry-pick the current overlay plus any required later functional fixes. Refresh
the consolidated overlay after review, excluding historical maintenance files
such as `UPDATING-LND-NOTES.md` under the shared patch-review rules.

Preserve these resources and behavior:

- Three architecture Dockerfiles, publish workflow, startup scripts and
  `.github/workflows/btcpay-tests.yml` / `btcpay/test-startup-tests.sh`.
- Build tags including `routerrpc watchtowerrpc kvdb_sqlite` and the upstream
  Makefile/Dockerfile adaptations.
- File-based Bitcoin RPC credentials, safe password migration and native macaroon
  rotation. Inspect the current overlay's scripts and tests to preserve their
  behavior, then run the startup regression suite described below.

Complete the [shared patch review](conventions.md#naming-and-patch-review), then
run `bash -n` on both startup scripts and the test script.

## 2. Review build dependencies

Check `go`/`toolchain` in `go.mod` and upstream's `GO_VERSION` in `Makefile`.
All three builders must satisfy those requirements; normally follow upstream's
toolchain. `GOTOOLCHAIN=local` means an older image will not download a new one.

- amd64 uses `golang:<version>-alpine`; ARM uses `golang:<version>-bookworm`.
- ARM builder stages stay pinned to `$BUILDPLATFORM` and cross-compile via
  `GOARCH`; otherwise Buildx emulates the entire Go compile.
- ARM runtimes use Bookworm too. Do not restore Bullseye runtime images whose
  package mirrors previously caused 404s.
- Bookworm has no `qemu` metapackage; retain `qemu-user-static qemu-user
  binfmt-support` rather than reintroducing `qemu`.
- Carry Loop forward unless deliberately updating it after compatibility review.
  Update its clone tag in all three Dockerfiles, smoke checks and master README.
  Inspect the current Dockerfiles to determine the bundled Loop version.

Verify base image availability for every target; do not assume an upstream Go
bump automatically updated our architecture-specific Dockerfiles.

## 3. Build and test before tagging

```bash
docker build --pull -t local-lnd:test -f linuxamd64.Dockerfile .
docker buildx build --platform linux/arm64 --pull --load \
  -t local-lnd:test-arm64 -f linuxarm64v8.Dockerfile .
docker run --rm --entrypoint lnd local-lnd:test --version
docker run --rm --entrypoint loop local-lnd:test --version
docker run --rm --platform linux/arm64 --entrypoint lnd local-lnd:test-arm64 --version
bash btcpay/test-startup-tests.sh --list
bash btcpay/test-startup-tests.sh
```

If ARM emulation is missing, obtain approval before host-wide privileged
registration: `docker run --privileged --rm tonistiigi/binfmt --install arm64,arm`.
Test amd64 and at least one ARM locally; publication must validate all three.

Startup tests require a Linux Docker host, curl and jq. They create disposable
regtest nodes, funded channels, networks and volumes, then clean them up. The
suite mounts the checkout's scripts. Inspect its `IMAGE` selection to determine
which binary it tests; do not assume it uses the newly built image. If the script
assigns `IMAGE` unconditionally, setting an environment variable will not override
it: make and review an explicit test-script change instead. Keep CI scenario
groups aligned with `--list`.

## 4. LND publication settings

Follow [shared publication](conventions.md#publication) with the captured `VERSION`
and these settings:

| Setting | Value |
| --- | --- |
| `PROJECT` | `lnd` |
| `WORKFLOW` | `publish.yml` |
| Release branch | `lnd/$UPSTREAM_TAG` |
| Secrets | `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` |
| Executable checks | `lnd --version`, `loop --version` |

The workflow pushes architecture suffixes `-amd64`, `-arm32v7`, `-arm64v8`, then
assembles the index. Prepare the version branch before tagging:

```bash
git push -u origin "lnd/$UPSTREAM_TAG"
git ls-remote origin "refs/heads/lnd/$UPSTREAM_TAG"
```

An RC and final LND release can print the same version: check embedded commit
identity and the `-fresh-btcpay` suffix, not just the version number.
If expected CI does not appear, inspect Actions settings: inherited upstream
workflows may be disabled separately.
Deleting CircleCI configuration alone does not disconnect its integration.

## 5. Test the published image's startup

Before [downstream updates](conventions.md#downstream-updates), repeat the full
startup suite against the **new published image**. Select the new tag through the
suite's supported configuration. If that requires a script change, use a temporary
validation branch from the exact release source, changing only the image selection.
Run locally or dispatch `btcpay-tests.yml` on the release or validation
branch and require every group to pass. Verify logs pulled the intended image
and retain source/run evidence. Keep mounted startup scripts identical to the
release, and verify the scripts packaged in the image separately. Clean up only
that temporary branch after validation; do not modify the published source/tag.

## 6. LND downstream references

Follow the [shared downstream process](conventions.md#downstream-updates) using:

- Library: `lnd` and `lnd_dest` in `tests/docker-compose.yml`.
- Core: `merchant_lnd` and `customer_lnd` in each shared Compose path.
- Deployment: `docker-compose-generator/docker-fragments/bitcoin-lnd.yml`.

## 7. Maintain master

LND uses version branches plus merges into `master`; do not rewrite it to mimic
Core Lightning. Preserve references to intervening releases and review the merge
tree against the approved release. Historically this used an `ours` merge with
the new release tree loaded into the index; it can overwrite master-only changes,
so do not perform it blindly. Inventory master-only fixes, retain the BTCPay
README/version list, and keep the centralized-instructions link rather than
restoring old maintenance documentation from an overlay.

Commit README version entries separately. Entries link the **amd64 platform
digest**, not the index digest, and state the bundled Loop version. Review the
master update through a PR, then follow the shared submodule-pin handoff rules.
