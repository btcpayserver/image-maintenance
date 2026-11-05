# Shared maintenance conventions

## Boundaries and preparation

- Keep maintenance instructions here. Keep necessary source patches, Dockerfiles,
  entrypoints, regression tests and publishing CI in the forks.
- Verify a clean worktree and record the starting branch/commit before switching.
  Do not run submodule updates over someone else's work.
- Verify upstream releases from authoritative repositories, including the peeled
  tag commit. Read release notes for compatibility and security implications.
  Do not select prereleases unless explicitly requested or already intentional.
- Inventory the previous released patch set AND subsequent fixes on maintenance
  branches. A release tag alone may omit important unreleased corrections.
- Use a new local preparation branch. Separate clones are safest for concurrent
  agents. Do not share a worktree between simultaneous updates.

## Select the upstream release

Use GitHub's latest published release for the upstream repository, queried with
`bash scripts/check.sh latest <project>`. The helper uses `gh release view`
without a tag and prints only the selected tag, ready for command substitution.
GitHub excludes drafts and releases marked as prereleases from this selection;
do not reject a release solely because its tag contains `-beta`, as LND's normal
releases do. If the query fails, stop and investigate rather than guessing a tag.

The project guides capture this as `UPSTREAM_TAG` and initialize `VERSION` from it,
so fetching, branch preparation and publication reuse the same discovered version.
Read the selected release's notes. Compare it with the fork's published
`basedon-*` tags and images, checking successful publication rather than assuming
a Git tag proves an image exists. If that upstream version is already published, no upstream bump is
needed; another image revision is a separate change. Do not downgrade if our
current image intentionally tracks a newer release. Verify the candidate's
upstream tag and peeled commit before preparing patches.

## Naming and patch review

- First image of `$UPSTREAM_TAG`: Git tag `basedon-$VERSION`, image `$VERSION`,
  with `VERSION=$UPSTREAM_TAG`.
  Preserve upstream suffixes such as LND's `-beta`.
- Subsequent images of that release: append `-1`, `-2`, etc. Check existing tags
  AND registry artifacts before selecting a revision. Never overwrite a published
  tag or publish different source under an existing image version. Append the
  revision to `VERSION`, not `UPSTREAM_TAG`.
- Prefer `maintenance/$PROJECT-$UPSTREAM_TAG` for preparation and
  `docs/image-maintenance` for documentation-only PRs. Preserve existing release
  branches: LND `lnd/$UPSTREAM_TAG`; Core Lightning `btcpaymaster`.
- Compare the old and new patch sets with `git range-diff`, inspect upstream
  conflict resolutions, and run `git diff --check`. Do not introduce unrelated
  formatting or cleanup. Do not blindly replay historical instruction files.
- LND may refresh its consolidated overlay; Core Lightning keeps its functional
  patches separate and ordered. Do not impose a common history rewrite strategy.
- Exclude historical agent instructions and maintenance documentation now owned
  by this repository; retain upstream and product-level test documentation.

When reviewing the previous release, record its verified upstream tag in
`PREVIOUS_UPSTREAM_TAG` and its published fork tag in `PREVIOUS_IMAGE_TAG`.
Use those variables in patch comparisons. Do not assume the latter is simply
`basedon-$PREVIOUS_UPSTREAM_TAG`: an image revision may have an additional suffix.

## Publication

Preparing a PR is not authorization to publish, merge, force-push shared branches,
or delete/move tags. Obtain explicit approval for each applicable release action.
Privileged binfmt registration changes the host: confirm it is acceptable first.

Before publishing:

1. Record exact upstream, overlay commits, intended source SHA and image tag.
2. Review checks AND inline review comments; resolve valid findings.
3. Confirm the tag is absent locally/remotely and the registry tag is unused.
4. Confirm the fork's current publishing workflow, secret names and repository
   configuration; do not copy credentials here or standardize secrets casually.
5. Verify the annotated release tag peels to the approved source commit.

Both forks publish from `basedon-*` tag pushes, not ordinary branch pushes. Set
`PROJECT` (`lnd` or `lightning`), `WORKFLOW` (from the project guide), `VERSION`
(the full image version including `v` and any suffix), and `SOURCE` (the approved
full source commit SHA). Complete the project's release-branch preparation and
verify its remote tip equals `SOURCE` before tagging.

From this repository root, check Git tag availability; check Docker Hub separately:

```bash
bash scripts/check.sh tag "$PROJECT" "basedon-$VERSION" --require-absent
```

Then, inside the corresponding fork, after approval:

```bash
git tag -a "basedon-$VERSION" -m "BTCPay $PROJECT $VERSION" "$SOURCE"
test "$(git rev-parse "basedon-$VERSION^{commit}")" = "$SOURCE"
git push origin "basedon-$VERSION"
gh run list --repo "btcpayserver/$PROJECT" --workflow "$WORKFLOW" --branch "basedon-$VERSION"
gh run watch <run-id> --repo "btcpayserver/$PROJECT" --exit-status
```

After publishing:

1. Watch the tag-triggered workflow through successful completion.
2. Verify the published index has `linux/amd64`, `linux/arm64`, `linux/arm/v7`.
3. Verify each platform's architecture and source identity against the approved
   commit using attestations and embedded binary identity as available. Run the
   published executables' version checks, not just locally built binaries.
   Distinguish native execution from static inspection of ARM binaries.
4. Record index/platform digests, workflow URLs, tests and compatibility notes in
   the coordinating issue or PR. Never record wallet passwords, seeds or tokens.
5. Complete any project-specific post-publication tests before downstream PRs.

From this repository root, inspect the published platform index and provenance:

```bash
bash scripts/check.sh image "btcpayserver/$PROJECT:$VERSION"
docker buildx imagetools inspect "btcpayserver/$PROJECT:$VERSION" \
  --format '{{json .Provenance}}'
```

## Downstream updates

After successful publication, artifact verification and project-specific tests,
read each downstream repository's current instructions.

Downstream image-reference updates do **not** require local testing. Make the
changes (including required generated files), commit and push them, open the PR,
then validate through CI on the current PR head. Inspect logs for the intended
image and executed project tests; fix failures rather than disabling tests.
Old-image green CI is not evidence for the new image. Do not set up a local
deployment or run local integration suites for these PRs; successful image
publication and project-specific post-publication checks remain prerequisites.

Proceed in this order:

1. **BTCPayServer.Lightning**: Update the project's two services in
   `tests/docker-compose.yml`. Open the library integration PR.
2. **btcpayserver**: Update the project's merchant/customer services in
   `BTCPayServer.Tests/docker-compose.yml`, `docker-compose.altcoins.yml`,
   `docker-compose.mutinynet.yml`, and `docker-compose.testnet.yml`. Open the
   core integration PR, linking the library PR and published source/image.
3. **btcpayserver-docker**: Only after both integration suites pass, update the
   project's deployment fragment and prepare the deployment PR as described below.

The project guides identify service names and deployment fragments. Keep exact
revision/RC/test suffixes in every image reference; do not accidentally promote
test candidates to production. Core CI currently exercises regtest through the
altcoins Compose file, not all four environments; do not claim broader coverage.

For the deployment PR:

- Follow btcpayserver-docker's
  [AGENTS.md](https://github.com/btcpayserver/btcpayserver-docker/blob/master/AGENTS.md)
  and PR skill. Regenerate `contrib/build-all-images.sh` and
  `docs/supported-images.md` with `contrib/DockerFileBuildHelper/update-repo.sh`;
  do not hand-edit generated sections or run the generated build-all script.
   Update verified source mappings only when needed.
- Open as draft, link both integration PRs and validation evidence, and request
  release-maintainer review (`@NicolasDorier` and `@Pavlenex`). Require Docker
  repository CI too.
- Never run `.github/scripts/test-install.sh` on a development machine: it removes
  the host Docker installation and belongs on disposable CI runners.

No step grants automatic merge or deployment authority. After the project's
release-history maintenance, restore the original submodule pin unless proposing
a reviewed pin update to verified published source. Never pin an unmerged PR tip.

Keep PR titles and descriptions consistent across images: summary of meaningful
changes, upstream/source/image links, compatibility actions when required, and
validation evidence (or a link to it). Downstream repository-specific PR policies
take precedence. Capitalize the first word of prose bullets.

## Failure recovery

Rerun infrastructure failures against the same source. Changed source needs a new
revision. Cancel an accidentally triggered publication and inspect partial registry
artifacts before deciding recovery with a maintainer. A canceled run is not proof
that nothing was pushed. Tag deletion or recreation needs explicit approval;
never recycle a published version. Other clones can retain stale tags after a
remote tag changes, and historical Actions runs retain their original tag SHA.
If a maintainer authorizes repairing a stale local tag, verify the remote peeled
target before deleting and fetching only that local tag; ordinary fetch does
not overwrite it. Wait for cancellation of a mistaken publication before recovery.

To compare targets without modifying refs:

```bash
bash scripts/check.sh tag "$PROJECT" "basedon-$VERSION"
```
