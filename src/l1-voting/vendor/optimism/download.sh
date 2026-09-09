#!/usr/bin/env bash
#
# Re-fetches the vendored OP Stack MPT/RLP libraries and applies a patch
set -euo pipefail

# ethereum-optimism/optimism, tag op-contracts/v6.0.0, pinned by commit for reproducibility
TAG="op-contracts/v6.0.0"
COMMIT="018f5ae926ec3277746b56a1c4ddb715c568603d"
BASE="https://raw.githubusercontent.com/ethereum-optimism/optimism/${COMMIT}/packages/contracts-bedrock/src/libraries"

cd "$(dirname "${BASH_SOURCE[0]}")"

find . -name "*.sol" -type f -delete

for f in Bytes.sol rlp/RLPReader.sol rlp/RLPErrors.sol trie/MerkleTrie.sol trie/SecureMerkleTrie.sol; do
    mkdir -p "$(dirname "$f")"
    echo "fetching $f"
    curl -fsSL "${BASE}/${f}" -o "$f"
done

git apply vendor.patch

echo "vendored from ethereum-optimism/optimism@${COMMIT} (${TAG})"
