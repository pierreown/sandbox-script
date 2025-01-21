# Sandbox Shell Script

该存储库包含一个通用的沙盒 Shell 脚本，旨在创建用于测试和调试的隔离环境。该脚本利用 unshare、overlayfs、pivot_root 等功能来构建一个轻量级和临时的类似容器的环境。它支持 root 和 rootless 模式以获得最大的灵活性。

## 特性

-   Root 和非 Root 模式：根据用户权限自动调整沙箱设置。
-   WSL2 支持：WSL2 环境下的支持。

## 使用方法

```text
Usage: ./sandbox.sh [options] [-- command [args...]]

Options:
  -n, --name=string               Set sandbox name
  -w, --work-dir=string           Set working directory
  -E, --preserve-env              Preserve environment variables
      --preserve-env=list         Preserve environment variables in list, separated by commas
                                  Note: NAME,USER,LOGNAME,HOME are always reset
      --mount-wsl                 Mount WSL support directories
      --mount-extra=list          Mount extra directories, separated by commas
  -h, --help                      Show usage

Examples:
  ./sandbox.sh -- /bin/bash -l
  ./sandbox.sh --preserve-env=PATH -- env
```

## 依赖

内核:

| Module    | Description                                   |
| --------- | --------------------------------------------- |
| namespace | MOUNT, UTS, IPC, PID, USER, CGROUP namespaces |
| overlayfs | Overlay filesystem support                    |

工具:

| Package        | Command                                               | Description                                |
| -------------- | ----------------------------------------------------- | ------------------------------------------ |
| dash           | `sh`                                                  | POSIX-compatible shell                     |
| mount          | `mount` `umount`                                      | Filesystem mounting utilities              |
| coreutils      | `echo` `head` `tr` `md5sum` `rm` `mkdir` `mknod` `id` | GNU core utilities                         |
| util-linux     | `unshare` `pivot_root` `getopt`                       |                                            |
| hostname       | `hostname`                                            |                                            |
| fuse-overlayfs | `fuse-overlayfs`                                      | User-Space overlay filesystem for rootless |
