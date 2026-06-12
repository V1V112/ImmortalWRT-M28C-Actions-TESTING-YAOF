# Local BBRv3 Integration

This project carries its own BBRv3 kernel patch sets and selects the matching
set automatically during the GitHub Actions build.

## Default Behavior

BBRv3 is enabled by default in both workflows through this boolean input:

```text
enable_bbrv3=true
```

When enabled, `scripts/stage-bbrv3-patches.sh` detects the Rockchip
`KERNEL_PATCHVER` from `target/linux/rockchip/Makefile`, then stages matching
patches from `patches/kernel/bbrv3/kernel-<kernel-version>/bbr3/*.patch` into
`target/linux/generic/backport-<kernel-version>/`.

Current local patch sets:

```text
patches/kernel/bbrv3/kernel-6.12/bbr3/
patches/kernel/bbrv3/kernel-6.18/bbr3/
```

If ImmortalWrt moves to a kernel version that is not present here, the script
fails early and prints the available local kernel versions.

## Disable BBRv3

Set this workflow input to false:

```text
enable_bbrv3=false
```

When disabled:

1. Local BBRv3 patches are not staged.
2. The build uses ImmortalWrt's default `tcp_bbr.c`, treated as BBR v1.
3. `kmod-tcp-bbr` is still built from `profiles/m28c/packages.txt`.
4. `kmod-sched` is still built from `profiles/m28c/packages.txt`; this package
   provides `sch_fq.ko`, which is required by `net.core.default_qdisc=fq`.
5. `files/etc/sysctl.d/99-bbrv3.conf` still selects `fq` and `bbr`, so the
   active algorithm is the default BBR implementation from the built kernel.

## fq qdisc Support

For BBR, use Linux `fq`, not `fq_codel` or `fq_pie`. In the ImmortalWrt
`openwrt-25.12` kernel module definitions, `sch_fq` is provided by
`kmod-sched`. If `tc qdisc ... fq` fails with `Specified qdisc not found`,
check that the final build config contains:

```text
CONFIG_PACKAGE_kmod-sched=y
CONFIG_PACKAGE_kmod-tcp-bbr=y
CONFIG_PACKAGE_tc-full=y
```

Runtime checks:

```sh
lsmod | grep sch_fq
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
tc qdisc replace dev eth0 root fq
tc -s qdisc show dev eth0
```

## BBR Version Display And Consistency

Both workflows show BBR twice:

1. After kernel patches are staged.
2. After firmware compilation finishes.

With BBRv3 enabled, the first step reads `BBR_VERSION` from the staged local
patch set, and the second step reads it from
`build_dir/.../net/ipv4/tcp_bbr.c`.

With BBRv3 disabled, the workflows record and compare `BBR_VERSION=1`, because
the default upstream BBR implementation does not carry a `BBR_VERSION` macro.

The second step compares the before/after values. If they differ, the workflow
fails. Both steps print a visible log block, emit a GitHub Actions notice, and
write the detected version and source path to the workflow Step Summary.

## Maintenance Knobs

Override these environment variables in the workflow when needed:

```bash
BBRV3_PATCH_ROOT=/path/to/patches/kernel/bbrv3
BBRV3_PATCH_SUBDIR=bbr3
```
