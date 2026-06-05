# YAOF BBRv3 Integration

This project can use the BBRv3 kernel patch set from QiuSimons/YAOF during the
GitHub Actions build.

## Default Behavior

BBRv3 is enabled by default in both workflows through this boolean input:

```text
enable_bbrv3=true
```

When enabled, `scripts/stage-yaof-bbrv3.sh` fetches YAOF and stages
`PATCH/kernel/bbr3/*.patch` into
`target/linux/generic/backport-<kernel-version>/`.

## Disable BBRv3

Set this workflow input to false:

```text
enable_bbrv3=false
```

When disabled:

1. YAOF BBRv3 patches are not fetched or staged.
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

With BBRv3 enabled, the first step reads `BBR_VERSION` from the staged YAOF
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
YAOF_REPO_URL=https://github.com/QiuSimons/YAOF.git
YAOF_BBRV3_REF=25.12
YAOF_BBRV3_PATCH_DIR=PATCH/kernel/bbr3
```
