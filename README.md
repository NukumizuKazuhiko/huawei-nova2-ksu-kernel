# Huawei Nova2 KSU Kernel

Huawei Nova 2 (PRA-LX1 / PIC-AL00) hi6250 Kernel 4.4.23 + SukiSU-Ultra.

## 构建

源码在 Release 附件 `kernel_4.4.23.tar.gz`。推送后手动触发 Actions 或创建 tag 自动构建。

## 流程

`.github/workflows/build.yml` 会:
1. 下载 Release 源码包并解压
2. 下载 aarch64-linux-android-4.9 工具链
3. 集成 SukiSU (setup.sh)
4. 编译内核 (Image.gz)
5. 上传产物到 workflow artifacts / Release
