#!/usr/bin/env bash
# Read-only patch, Git tag and multi-platform image checks.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
    cat <<'EOF'
Usage:
  bash scripts/check.sh latest <lnd|lightning>
  bash scripts/check.sh patches <lnd|lightning> <upstream> <candidate>
      [--previous <old-upstream> <old-candidate>]
  bash scripts/check.sh tag <lnd|lightning> <name>
      [--remote <remote>] [--require-absent]
  bash scripts/check.sh image <image:tag>

Checks never fetch, check out, push, build, or run containers.
Image inspection requires jq and Docker Buildx. Tag checks contact the Git remote.
Latest-release lookup requires gh and prints only the upstream tag for shell use.
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

project_repo() {
    case "$1" in lnd|lightning) ;; *) die "Unknown project: $1" ;; esac
    REPO="$ROOT/submodules/$1"
    [[ -e "$REPO/.git" ]] || die "Initialize submodule first: $REPO"
}

commit() {
    git -C "$REPO" rev-parse --verify --end-of-options "$1^{commit}"
}

latest() {
    [[ $# == 1 ]] || die "Expected one project (lnd or lightning)"
    local upstream tag
    case "$1" in
        lnd) upstream=lightningnetwork/lnd ;;
        lightning) upstream=ElementsProject/lightning ;;
        *) die "Unknown project: $1" ;;
    esac
    tag=$(gh release view --repo "$upstream" --json tagName --jq .tagName)
    [[ -n $tag && $tag != null ]] || die "GitHub returned no release tag"
    git check-ref-format "refs/tags/$tag" || die "GitHub returned an invalid release tag"
    printf '%s\n' "$tag"
}

patches() {
    [[ $# == 3 || $# == 6 ]] || die "See --help for patches arguments"
    project_repo "$1"
    local base tip old_base old_tip
    base=$(commit "$2")
    tip=$(commit "$3")
    git -C "$REPO" merge-base --is-ancestor "$base" "$tip" || die "Upstream is not an ancestor of candidate"
    printf 'Upstream: %s (%s)\nCandidate: %s (%s)\n' "$2" "$base" "$3" "$tip"
    git -C "$REPO" log --reverse --oneline "$base..$tip" --
    git -C "$REPO" diff --stat "$base" "$tip" --
    git -C "$REPO" diff --check "$base" "$tip" --
    if [[ $# == 6 ]]; then
        [[ $4 == --previous ]] || die "Expected --previous"
        old_base=$(commit "$5")
        old_tip=$(commit "$6")
        git -C "$REPO" merge-base --is-ancestor "$old_base" "$old_tip" || die "Previous upstream is not an ancestor"
        git -C "$REPO" range-diff --no-color "$old_base..$old_tip" "$base..$tip"
    fi
}

tag() {
    [[ $# -ge 2 ]] || die "See --help for tag arguments"
    project_repo "$1"
    local ref="refs/tags/$2" remote=origin require_absent=false status
    local local_object='' local_target='' remote_object='' remote_target='' refs sha remote_ref
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --remote) [[ $# -ge 2 ]] || die "--remote needs a value"; remote=$2; shift 2 ;;
            --require-absent) require_absent=true; shift ;;
            *) die "Unknown tag option: $1" ;;
        esac
    done
    git -C "$REPO" check-ref-format "$ref"
    # Only status 1 means an absent ref; do not hide other Git failures.
    if git -C "$REPO" show-ref --verify --quiet "$ref"; then
        local_object=$(git -C "$REPO" rev-parse --verify "$ref")
        local_target=$(commit "$ref")
    else
        status=$?
        [[ $status == 1 ]] || exit "$status"
    fi
    refs=$(git -C "$REPO" ls-remote --tags -- "$remote" "$ref" "$ref^{}")
    while read -r sha remote_ref; do
        case "$remote_ref" in
            "$ref") remote_object=$sha ;;
            "$ref^{}") remote_target=$sha ;;
        esac
    done <<< "$refs"
    remote_target=${remote_target:-$remote_object}
    printf 'Local tag object: %s\nLocal commit: %s\nRemote tag object: %s\nRemote commit: %s\n' \
        "${local_object:-absent}" "${local_target:-absent}" "${remote_object:-absent}" "${remote_target:-absent}"
    if $require_absent && [[ -n $local_object || -n $remote_object ]]; then
        die "Tag already exists; do not overwrite it"
    fi
    if [[ -n $local_object && -n $remote_object ]]; then
        [[ $local_object == "$remote_object" && $local_target == "$remote_target" ]] ||
            die "Local and remote tags differ; inspect before proceeding"
        echo "Local and remote tags match"
    elif [[ -z $local_object && -z $remote_object ]]; then
        echo "Tag is available in Git; registry availability must be checked separately"
    else
        echo "Tag exists on only one side; inspect before proceeding"
    fi
}

image() {
    [[ $# == 1 && $1 != -* ]] || die "Expected one image reference"
    local raw platforms platform digest missing=()
    raw=$(docker buildx imagetools inspect --raw "$1")
    # Ignore attestation descriptors; arm64/v8 and arm64 are equivalent here.
    platforms=$(jq -er '
        if (.manifests | type) != "array" then error("Expected an image index") else . end
        | [.manifests[] | select(.platform.os != null and .platform.architecture != null)
          | select(.platform.os != "unknown" and .platform.architecture != "unknown")
          | {name: (.platform.os + "/" + .platform.architecture
              + (if .platform.variant != null and .platform.variant != ""
                    and (.platform.architecture != "arm64" or .platform.variant != "v8")
                 then "/" + .platform.variant else "" end)), digest: .digest}
          | if (.digest | type) != "string" then error("Missing platform digest") else . end]
        | .[] | [.name, .digest] | @tsv' <<< "$raw")
    while IFS=$'\t' read -r platform digest; do
        printf '%s: %s\n' "$platform" "$digest"
    done <<< "$platforms"
    for platform in linux/amd64 linux/arm64 linux/arm/v7; do
        if ! grep -q -- "^$platform"$'\t' <<< "$platforms"; then
            missing+=("$platform")
        fi
    done
    [[ ${#missing[@]} == 0 ]] || die "Image index missing platforms: ${missing[*]}"
    echo "All required platforms present; executable smoke tests are still required"
}

[[ $# -gt 0 ]] || { usage >&2; exit 1; }
command=$1
shift
case "$command" in
    -h|--help) usage ;;
    latest) latest "$@" ;;
    patches) patches "$@" ;;
    tag) tag "$@" ;;
    image) image "$@" ;;
    *) die "Unknown command: $command (see --help)" ;;
esac
