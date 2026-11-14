# SukiSU 5.4 compatibility patches

These patches apply to `SukiSU-Ultra/SukiSU-Ultra` commit
`f9aa2fec23c3f4a06a935f69dc04cb85b261e7f3` (branch `builtin`).

They are applied by `scripts/apply-patches.sh` after cloning SukiSU and before
the manual hook script runs. `sha256sums` pins each patch; `pins.env` pins the
checksum of the manifest.

| Patch | Why |
| --- | --- |
| `0001-5.4-guard-static-call-include.patch` | `kernel/kernel_includes.h` includes `<linux/static_call.h>` unconditionally. The header only exists on Linux >= 5.10, and this tree does not use `static_call` from that include. |
| `0002-5.4-fix-unused-selinux-policy-vars.patch` | `selinux/rules.c` declares `pol`/`old_pol` outside the `>= 5.10` branch. On 5.4 they are unused, which fails with `-Werror`. Move the declaration into the version-guarded block. |
