#!/usr/bin/env bash
# Offline fixtures: no Docker daemon, credentials, network or submodules needed.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/image-maintenance-tests.XXXXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/scripts" "$WORK/submodules/lnd" "$WORK/bin"
cp "$ROOT/scripts/check.sh" "$WORK/scripts/check.sh"
CHECK="$WORK/scripts/check.sh"
REPO="$WORK/submodules/lnd"
OUTPUT="$WORK/output"
COUNT=0

pass() { COUNT=$((COUNT + 1)); printf 'ok %s - %s\n' "$COUNT" "$*"; }
contains() { grep -qF -- "$1" "$OUTPUT" || { cat "$OUTPUT"; exit 1; }; }
fails() {
    if bash "$CHECK" "$@" > "$OUTPUT" 2>&1; then
        echo "Unexpected success: $*" >&2
        exit 1
    fi
}
check() { bash "$CHECK" "$@" > "$OUTPUT" 2>&1; }

# Keep fixture commits independent of the maintainer's Git signing/hooks config.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Test GIT_COMMITTER_NAME=Test
export GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_EMAIL=test@example.com
git init --bare -q "$WORK/remote.git"
git init -q "$REPO"
git -C "$REPO" remote add origin "$WORK/remote.git"
git -C "$REPO" commit --allow-empty -qm Upstream
git -C "$REPO" tag v1
git -C "$REPO" commit --allow-empty -qm Overlay
git -C "$REPO" tag -a basedon-v1 -m Release

check --help
contains Usage
pass help
fails
pass 'missing command'
fails unknown
pass 'unknown command'
fails patches unknown v1 HEAD
pass 'unknown project'
fails patches lightning v1 HEAD
pass 'uninitialized submodule'
fails tag lnd basedon-v1 --remote
pass 'missing option argument'
check patches lnd v1 basedon-v1 --previous v1 basedon-v1
contains Overlay
[[ $(git -C "$REPO" status --porcelain) == '' ]]
[[ $(git -C "$REPO" rev-parse HEAD) == "$(git -C "$REPO" rev-parse 'basedon-v1^{commit}')" ]]
pass 'patch inventory, range diff and unchanged checkout'
fails patches lnd missing HEAD
pass 'missing ref'
fails patches lnd HEAD v1
contains 'not an ancestor'
pass 'nonancestor ref'
printf 'trailing whitespace  \n' > "$REPO/overlay.txt"
git -C "$REPO" add overlay.txt
git -C "$REPO" commit -qm Whitespace
fails patches lnd v1 HEAD
contains 'trailing whitespace'
pass 'whitespace diagnostics'
check tag lnd basedon-new --require-absent
contains 'available in Git'
pass 'absent tag'
check tag lnd basedon-v1
contains 'one side'
pass 'local-only tag'
git -C "$REPO" tag lightweight
for tag in basedon-v1 lightweight; do
    git -C "$REPO" push -q origin "refs/tags/$tag"
    check tag lnd "$tag" --remote origin
    contains 'tags match'
    fails tag lnd "$tag" --require-absent
    contains 'already exists'
done
pass 'annotated and lightweight tags match; existing tags rejected'
git -C "$REPO" tag -d basedon-v1 > /dev/null
check tag lnd basedon-v1
contains 'one side'
fails tag lnd basedon-v1 --require-absent
pass 'remote-only tag'
git -C "$REPO" tag -a basedon-v1 -m 'Different object' lightweight
fails tag lnd basedon-v1
contains 'tags differ'
pass 'different target rejected'
git -C "$REPO" tag -fa lightweight -m 'Different object at same commit' > /dev/null
fails tag lnd lightweight
contains 'tags differ'
pass 'different tag object at same commit rejected'
fails tag lnd 'bad tag'
pass 'invalid tag name'
fails tag lnd new --remote missing
pass 'remote errors are not mistaken for absent tags'

# Assert latest lookup selects the correct upstream and needs no submodule.
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    'release view --repo lightningnetwork/lnd --json tagName --jq .tagName') default=vLATEST-beta ;;
    'release view --repo ElementsProject/lightning --json tagName --jq .tagName') default=vLATEST ;;
    *) echo "Unexpected GitHub query: $*" >&2; exit 1 ;;
esac
[[ ${GH_FAIL:-false} == false ]] || { echo 'GitHub unavailable' >&2; exit 1; }
printf '%s\n' "${GH_TAG-$default}"
EOF
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
check latest lnd
[[ $(cat "$OUTPUT") == vLATEST-beta ]]
pass 'latest LND release preserves the full tag'
check latest lightning
[[ $(cat "$OUTPUT") == vLATEST ]]
pass 'latest CLN release without an initialized submodule'
fails latest unknown
pass 'unknown release project'
fails latest
pass 'missing release project'
export GH_TAG=''
fails latest lnd
contains 'no release tag'
export GH_TAG=null
fails latest lnd
pass 'empty and null release tags rejected'
export GH_TAG='bad tag'
fails latest lnd
contains 'invalid release tag'
pass 'invalid release tag rejected'
unset GH_TAG
export GH_FAIL=true
fails latest lnd
contains 'GitHub unavailable'
pass 'GitHub failure propagated without a guessed version'
unset GH_FAIL

# A fake Docker command asserts the helper only inspects the requested index.
cat > "$WORK/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'buildx imagetools inspect --raw example/image:v1' ]]
[[ ${DOCKER_FAIL:-false} == false ]] || { echo 'registry unavailable' >&2; exit 1; }
cat "$IMAGE_FIXTURE"
EOF
chmod +x "$WORK/bin/docker"
export PATH="$WORK/bin:$PATH" IMAGE_FIXTURE="$WORK/index.json"
cat > "$IMAGE_FIXTURE" <<'EOF'
{"manifests":[
  {"digest":"sha256:a","platform":{"os":"linux","architecture":"amd64"}},
  {"digest":"sha256:b","platform":{"os":"linux","architecture":"arm64","variant":"v8"}},
  {"digest":"sha256:c","platform":{"os":"linux","architecture":"arm","variant":"v7"}},
  {"digest":"sha256:d","platform":{"os":"unknown","architecture":"unknown"}}
]}
EOF
check image example/image:v1
contains 'All required platforms'
if grep -q 'unknown/unknown' "$OUTPUT"; then
    echo 'Attestations must not be counted as runnable platforms' >&2
    exit 1
fi
pass 'platforms, arm64/v8 normalization and attestations'
jq 'del(.manifests[2])' "$IMAGE_FIXTURE" > "$WORK/missing.json"
cp "$WORK/missing.json" "$IMAGE_FIXTURE"
fails image example/image:v1
contains 'missing platforms: linux/arm/v7'
pass 'missing platform'
printf '{"schemaVersion":2}\n' > "$IMAGE_FIXTURE"
fails image example/image:v1
pass 'single manifest rejected'
printf 'not json\n' > "$IMAGE_FIXTURE"
fails image example/image:v1
pass 'invalid registry response'
export DOCKER_FAIL=true
fails image example/image:v1
contains 'registry unavailable'
pass 'registry failure propagated'

# Check inline local Markdown links without crawling upstream submodules.
for document in "$ROOT/README.md" "$ROOT/AGENTS.md" "$ROOT"/docs/*.md; do
    while IFS= read -r link; do
        target=${link:2:${#link}-3}
        case "$target" in *://*|\#*) continue ;; esac
        target=${target%%#*}
        [[ -e "$(dirname -- "$document")/$target" ]] || {
            echo "Broken link in $document: $target" >&2
            exit 1
        }
    done < <(grep -oE '\]\([^)]*\)' "$document" || true)
done
pass 'local documentation links'
printf 'Passed %s checks.\n' "$COUNT"
