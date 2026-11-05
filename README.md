# BTCPay Image Maintenance

Shared procedures and tools for maintaining BTCPay Server's Docker images.
Builds and publication remain in the individual forks; this repository does not
replace [dockerfile-deps](https://github.com/btcpayserver/dockerfile-deps).

## Getting started

```bash
git clone --recurse-submodules git@github.com:btcpayserver/image-maintenance.git
cd image-maintenance
# If already cloned:
git submodule update --init --recursive
```

SSH access to GitHub is required for these URLs. Run agents from this directory
so they read [AGENTS.md](AGENTS.md), not directly from a submodule.

| Image | Fork | Procedure |
| --- | --- | --- |
| `btcpayserver/lnd` | [lnd](https://github.com/btcpayserver/lnd) | [LND](docs/lnd.md) |
| `btcpayserver/lightning` | [lightning](https://github.com/btcpayserver/lightning) | [Core Lightning](docs/lightning.md) |

Read [shared conventions](docs/conventions.md) first. Submodules pin published
source snapshots, not necessarily their forks' default branches or the versions
currently deployed by BTCPay Server.
Local `upstream` remotes are not copied by cloning; each procedure shows how to
configure them. Do not use `git submodule update --remote` to choose a release.

## Read-only helpers

Requires Bash and Git; image inspection also requires jq and Docker Buildx.
Latest upstream release lookup requires GitHub CLI (`gh`).
Helpers never fetch, check out, change tags, push, build, or run containers.
Release lookup contacts GitHub, tag checks contact the configured Git remote,
and image checks contact its registry.

```bash
UPSTREAM_TAG=$(bash scripts/check.sh latest lnd)
bash scripts/check.sh tag lnd "basedon-$UPSTREAM_TAG"
# For an already published release, after fetching its upstream tag:
bash scripts/check.sh patches lnd "$UPSTREAM_TAG" "basedon-$UPSTREAM_TAG"
bash scripts/check.sh image "btcpayserver/lnd:$UPSTREAM_TAG"
bash scripts/check.sh --help
```

`patches` requires the upstream commit to be an ancestor of the candidate.
It fails on whitespace errors too, including preexisting ones in an overlay.
`tag` compares both tag objects and peeled commit targets; mismatches fail.
Add `--require-absent` when checking a tag before new publication.
`latest` prints only the upstream tag and fails on lookup errors or invalid tags;
the procedures capture it once and reuse it without manual version substitution.
`image` requires amd64, arm64 and arm/v7, prints platform digests, and ignores
attestation descriptors. It does not verify executable behavior: run the
procedure's version smoke tests separately.

## Adding another image

Add its fork under `submodules/`, document its upstream, patch inventory, build
and publication checks, then link the procedure from this README and AGENTS.md.
Prefer extending shared checks over adding another release automation system.

## Development

```bash
bash tests/check.sh
shellcheck scripts/check.sh tests/check.sh
```

Tests require Bash, Git and jq. They use temporary local Git repositories and
mocked registry responses; they do not need Docker, network access, credentials,
Python, or initialized submodules. CI also runs syntax checks and ShellCheck.
