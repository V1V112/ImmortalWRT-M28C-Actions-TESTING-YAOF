# YAOF BBRv3 集成说明

本项目在 GitHub Actions 编译过程中使用来自 QiuSimons/YAOF 的 BBRv3 内核补丁集。

## 工作原理

`scripts/stage-yaof-bbrv3.sh` 会在 ImmortalWrt 源码树克隆完成后、本地内核补丁 staged 之前运行。

该脚本会执行以下操作：

1. 从 `target/linux/rockchip/Makefile` 中检测 `KERNEL_PATCHVER`。
2. 拉取配置好的 YAOF 分支或标签。
3. 将 `PATCH/kernel/bbr3/*.patch` 复制到
   `target/linux/generic/backport-<kernel-version>/` 目录中。

固件仍然会根据 `profiles/m28c/packages.txt` 编译 `kmod-tcp-bbr`。

运行时，`files/etc/sysctl.d/99-bbrv3.conf` 会默认选择 `fq` 和 `bbr`。

## BBR 版本显示与一致性检查

两个 workflow 都会显示两次 BBR 版本：

1. 在内核补丁 staged 之后，`scripts/show-bbr-version.sh` 会从已 staged 的 BBR 补丁集中读取版本，并将其记录到
   `$OPENWRT_DIR/.bbr-version.before`。
2. 在固件编译完成后，同一个脚本会从 `build_dir/.../net/ipv4/tcp_bbr.c` 下已准备好的内核源码中读取版本。

第二步会对比这两个版本值。如果两者不一致，或者编译后的版本无法检测到，workflow 会失败。两个步骤都会打印清晰可见的日志块，输出 GitHub Actions notice，并将检测到的版本以及来源路径写入 workflow 的 Step Summary。

## 维护配置项

如有需要，可以在 workflow 中覆盖以下环境变量：

```bash
YAOF_REPO_URL=https://github.com/QiuSimons/YAOF.git
YAOF_BBRV3_REF=25.12
YAOF_BBRV3_PATCH_DIR=PATCH/kernel/bbr3