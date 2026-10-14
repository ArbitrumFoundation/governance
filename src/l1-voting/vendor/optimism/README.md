# Vendored OP Stack libraries

MPT / RLP helpers copied from the OP-Stack, used by `ProofHelper` to verify
`eth_getProof` account/storage proofs.

## Why vendored instead of a package

- The version we need (`op-contracts/v6.0.0`) only exists as a git tag; npm
  publishing of `@eth-optimism/contracts-bedrock` stopped at 0.17.3.
- The full package is ~128 MB (and `forge install` pulls the whole monorepo)
  for ~700 lines of library code.
- Upstream uses `src/libraries/...` imports that collide with this repo's own
  `src`, so any install path needs an import rewrite anyway.

Vendoring these 5 files keeps the subtree self-contained: no new dependencies,
no remappings, and auditors review exactly what compiles.

[download.sh](./download.sh) re-fetches the files (pinned to a commit) and
applies [vendor.patch](./vendor.patch), which only rewrites imports to relative
paths.
