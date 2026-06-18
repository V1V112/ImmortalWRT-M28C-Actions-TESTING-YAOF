# 本地 BBRv3 集成

本项目内置 BBRv3 内核补丁集，并会在 GitHub Actions 构建时自动选择与当前内核版本匹配的补丁。

## 默认行为

两个工作流都通过以下布尔输入默认启用 BBRv3：

```text
enable_bbrv3=true
```

启用后，`scripts/stage-bbrv3-patches.sh` 会从 `target/linux/rockchip/Makefile` 检测 Rockchip 目标使用的 `KERNEL_PATCHVER`，再把 `patches/kernel/bbrv3/kernel-<kernel-version>/bbr3/*.patch` 中匹配的补丁放入 `target/linux/generic/backport-<kernel-version>/`。

当前本地补丁集：

```text
patches/kernel/bbrv3/kernel-6.12/bbr3/
patches/kernel/bbrv3/kernel-6.18/bbr3/
```

如果 ImmortalWrt 切换到了本仓库尚未提供补丁的内核版本，脚本会提前失败，并打印当前可用的本地内核版本。

## 禁用 BBRv3

将工作流输入设置为 false：

```text
enable_bbrv3=false
```

禁用后：

1. 不会放置本地 BBRv3 补丁。
2. 构建会使用 ImmortalWrt 默认的 `tcp_bbr.c`，按 BBR v1 处理。
3. `kmod-tcp-bbr` 仍会通过 `profiles/m28c/packages.txt` 编入固件。
4. `kmod-sched` 仍会通过 `profiles/m28c/packages.txt` 编入固件；该软件包提供 `sch_fq.ko`，也就是 `net.core.default_qdisc=fq` 所需的模块。
5. `files/etc/sysctl.d/99-bbrv3.conf` 仍会选择 `fq` 和 `bbr`，因此实际启用的是当前内核自带的默认 BBR 实现。

## fq qdisc 支持

BBR 推荐使用 Linux `fq`，不是 `fq_codel` 或 `fq_pie`。在 ImmortalWrt `v25.12.0-rc2` 的内核模块定义中，`sch_fq` 由 `kmod-sched` 提供。如果 `tc qdisc ... fq` 报错 `Specified qdisc not found`，请检查最终构建配置是否包含：

```text
CONFIG_PACKAGE_kmod-sched=y
CONFIG_PACKAGE_kmod-tcp-bbr=y
CONFIG_PACKAGE_tc-full=y
```

运行时检查：

```sh
lsmod | grep sch_fq
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
tc qdisc replace dev eth0 root fq
tc -s qdisc show dev eth0
```

## BBR 版本显示与一致性

两个工作流会显示两次 BBR 版本：

1. 内核补丁放置完成后。
2. 固件编译完成后。

启用 BBRv3 时，第一次检测会从已放置的本地补丁集中读取 `BBR_VERSION`，第二次检测会从 `build_dir/.../net/ipv4/tcp_bbr.c` 中读取。

禁用 BBRv3 时，工作流会记录并比较 `BBR_VERSION=1`，因为上游默认 BBR 实现没有 `BBR_VERSION` 宏。

第二次检测会比较前后版本。如果版本不一致，工作流会失败。两次检测都会打印醒目的日志块，发送 GitHub Actions 通知，并把检测到的版本和来源路径写入工作流步骤摘要。

## 维护开关

必要时可在工作流中覆盖以下环境变量：

```bash
BBRV3_PATCH_ROOT=/path/to/patches/kernel/bbrv3
BBRV3_PATCH_SUBDIR=bbr3
```
