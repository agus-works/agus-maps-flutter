# CoMaps Patch Files

This directory contains optional patch files (`*.patch`) that may be applied to the CoMaps checkout in `thirdparty/comaps`.

Policy:
- Prefer a clean bridge layer in this repo.
- Only introduce patches if there is no viable clean integration path.
- Keep patches small, scoped, and re-applicable across tags.

Applied by:
- `./scripts/apply_comaps_patches.sh`
