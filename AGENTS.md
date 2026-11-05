# Image Maintenance

Start agents from this repository root. Read [shared conventions](docs/conventions.md)
and the relevant procedure before changing a fork:

- [LND](docs/lnd.md): `submodules/lnd`
- [Core Lightning](docs/lightning.md): `submodules/lightning`

This repository owns maintenance instructions and helper scripts. Forks own
product patches, Dockerfiles, entrypoints, tests and publishing workflows. Do not
add agent instructions or unrelated cleanup to the forks. Instructions remaining
in historical fork commits are archival; use this repository's procedures.

Inspect local changes, fork instructions, branches and remotes before working.
Never discard another maintainer's work. Use separate clones for concurrent
updates; submodules do not coordinate agents or provide locks.

An instruction to prepare a bump does not authorize publishing images, merging
PRs, rewriting shared branches, or deleting/moving tags. Obtain explicit approval
for those actions. Never move a published release tag or overwrite its image.

Keep submodule pins on deliberately selected, published source commits, never
on unmerged PR tips. Record validation evidence in the update's PR or issue.
Run `bash tests/check.sh` and `shellcheck scripts/check.sh tests/check.sh` after
changing helpers.
