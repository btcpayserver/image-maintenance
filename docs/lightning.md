# Updating Core Lightning

Read [shared conventions](conventions.md). Commands run in
`submodules/lightning` unless shown from the parent. Replace placeholders before
use. This fork publishes `btcpayserver/lightning`; it is not `BTCPayServer.Lightning`
(the .NET integration library), and is not built by `dockerfile-deps`.

## 1. Verify upstream and inventory patches

From this repository root, select upstream using the
[shared selection rules](conventions.md#select-the-upstream-release):

```bash
UPSTREAM_TAG=$(bash scripts/check.sh latest lightning)
VERSION=$UPSTREAM_TAG
```

Continue in `submodules/lightning` in the same shell.

Complete the [shared preparation checks](conventions.md#boundaries-and-preparation).
Confirm `origin` points to `btcpayserver/lightning`. Add `upstream` if missing;
otherwise verify its URL:

```bash
git remote add upstream https://github.com/ElementsProject/lightning.git
git fetch origin refs/heads/btcpaymaster:refs/remotes/origin/btcpaymaster
git fetch --no-tags upstream "refs/tags/$UPSTREAM_TAG:refs/tags/$UPSTREAM_TAG"
git ls-remote upstream "refs/tags/$UPSTREAM_TAG" "refs/tags/$UPSTREAM_TAG^{}"
```

Read the selected release notes with
`gh release view "$UPSTREAM_TAG" --repo ElementsProject/lightning`.
Record the [previous-release variables](conventions.md#naming-and-patch-review)
from verified history. Fetch the previous upstream tag if absent, then from the parent:

```bash
bash scripts/check.sh patches lightning "$PREVIOUS_UPSTREAM_TAG" "$PREVIOUS_IMAGE_TAG"
```

Use the shared patch inventory, including open/merged PRs, to identify the
required functional commits rather than relying on a fixed commit list.

Preserve Dockerfile packaging changes, Makefile version derivation,
`tools/docker-entrypoint.sh`, file-based Bitcoin RPC credentials in
`plugins/bcli.c`, and `.github/workflows/docker.yml`. Review conflicts without
dropping upstream changes or BTCPay behavior. Keep functional commits separate
and in their original order; review new fixes independently.

## 2. Prepare the linear update without rewriting shared history

`btcpaymaster` intentionally represents an upstream release plus BTCPay patches;
do not merge a new release into the old tip. Prepare on a new branch first:

```bash
git switch -c "maintenance/lightning-$UPSTREAM_TAG" "$UPSTREAM_TAG"
git cherry-pick <functional-overlay-sha> [<later-functional-fix> ...]
git diff --check "$UPSTREAM_TAG..HEAD"
git range-diff "$PREVIOUS_UPSTREAM_TAG..$PREVIOUS_IMAGE_TAG" "$UPSTREAM_TAG..HEAD"
bash -n tools/docker-entrypoint.sh
```

Differences should account for conflict resolutions, new fixes, and deliberate
removal of instruction-only commits. Open a review PR against `btcpaymaster` but
do not merge it: a merge commit defeats this fork's linear release strategy.
The PR is a review surface for the patch set; the approved branch replacement
below is a separate maintainer action.

Follow inherited CLN changelog conventions on PRs. Documentation-only changes
need `Changelog-None` in the PR description or a commit message; otherwise
pre-build checks stop before validating anything else.

## 3. Optional local validation

Local builds and startup/regression validation are not required before publishing.
Use CI for builds and relevant regression/integration checks. The commands below
are available for optional local troubleshooting, not as release prerequisites.

```bash
docker buildx build --platform linux/amd64 --pull --load -t local-cln:test .
docker run --rm --entrypoint lightningd local-cln:test --version
docker buildx build --platform linux/arm64 --pull --load -t local-cln:test-arm64 .
docker run --rm --platform linux/arm64 --entrypoint lightningd local-cln:test-arm64 --version
```

Obtain approval for privileged binfmt registration if local testing needs it.
Verify upstream's build dependencies and runtime packaging on all published
targets. Use relevant CI regression/integration checks for changed behavior;
a version smoke test alone does not validate startup or RPC credential handling.

## 4. Replace btcpaymaster only with explicit approval

After review, record the approved source SHA and the remote branch SHA being
replaced. The reviewed preparation branch is the replacement source; no hard
reset of a maintainer's local `btcpaymaster` is necessary:

```bash
expected_remote=$(git rev-parse origin/btcpaymaster)
git ls-remote origin refs/heads/btcpaymaster
git push --force-with-lease=refs/heads/btcpaymaster:$expected_remote \
  origin HEAD:refs/heads/btcpaymaster
git ls-remote origin refs/heads/btcpaymaster
```

Run this only from the approved preparation branch. If remote changes appeared
since review, stop and inspect them rather than refreshing the lease blindly.
Keep a reference to the previous tip for recovery. Close the review PR with the
replacement SHA after the approved rewrite; do not use GitHub's merge button.

## 5. Core Lightning publication settings

Follow [shared publication](conventions.md#publication) with the captured `VERSION`
and these settings:

| Setting | Value |
| --- | --- |
| `PROJECT` | `lightning` |
| `WORKFLOW` | `docker.yml` |
| Release branch | `btcpaymaster` |
| Secrets | `DOCKERHUB_USER`, `DOCKERHUB_PASS` |
| Repository variable | `DOCKERHUB_REPO=btcpayserver/lightning` |
| Executable check | `lightningd --version` |

The approved source must equal the remote `btcpaymaster` tip prepared above.
Verify the repository variable; do not change credentials as part of a routine
bump. Version output can include `basedon-` because the Makefile derives it from
the Git tag.

## 6. Core Lightning downstream references

Follow the [shared downstream process](conventions.md#downstream-updates) using:

- Library: `lightningd` and `lightningd_dest` in `tests/docker-compose.yml`.
- Core: `merchant_lightningd` and `customer_lightningd` in each shared Compose path.
- Deployment: `docker-compose-generator/docker-fragments/bitcoin-clightning.yml`.
