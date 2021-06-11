# mshell
终端 SSH 会话管理，同时支持CentOS，Ubuntu，Darwin，包括会话的增删改查、自动登录、文件/ssh-key批量推送等

## 使用场景
- 主要针对 Mac 用户，以避免安装多个 Terminal，推荐使用**iTerm2+mshell.sh**，则可同时支持 lrzsz 及 ssh 会话管理
- 跳板机的会话管理，支持简单的服务器批处理能力

## 功能列表
- 会话管理
  - session 增删改查
- 自动登录
  - ssh 自动应答
- 文件批量上传
  - scp 自动应答，支持文件/目录批量上传到多个会话、文件/目录批量拉取
- 公钥批量推送
  - ssh-copy-id 自动应答，ssh-key 批量推送到多个会话（使用默认目录，~/.ssh/，rsa 加密算法）
- todo
  - 会话分组
  - 命令/脚本批量执行

## 支持的 OS
 - Darwin
 - CentOS
 - Ubuntu

## 依赖说明（自动安装）
- sha1sum，用于生成 Session ID
- jq，用于 JSON 操作，Session 数据以 JSON 格式存储
- expect，用于支持自动登录

## 文件说明（默认存储在 ~/.mshell/）
- session.list，session 数据表
  - 可以手动编辑该文件，缓存会自动更新
  - 可以将该文件复制到新设备上，即可完成迁移
- session.cache，mshell ls 缓存
- ssh.exp，ssh 自动应答脚本
- scp.exp，scp 自动应答脚本
- pushkey.exp，ssh-copy-id 自动应答脚本

## 使用
```shell
Usage: mshell COMMAND [ARGS...]

  SSH session management for Mac terminal, while support CentOS,
  Ubuntu, Darwin, including automatic login, file exchange etc.

Managment Commands:
  add                                Create a new session
  remove ID [ID...], rm              Remove one or more sessions
  update ID                          Update information of a session
  inspect ID                         Display information of a session
  list, ls                           List sessions

Commands:
  ssh ID                             SSH to a session
  pull -f remote:local ID            Pull file or directory from a session
  push -f local:remote ID [ID...]    Push file or directory to one or more sessions
  pushkey ID [ID...]                 Copy the ssh-key to one or more sessions
```

## 示例
- 会话管理
![会话管理](https://github.com/goindow/mshell/blob/main/example/session-management.png)
- 文件拉取
![文件拉取](https://github.com/goindow/mshell/blob/main/example/pull.png)
- 文件批量上传
![文件批量上传](https://github.com/goindow/mshell/blob/main/example/push.png)
- 公钥批量推送
![公钥批量推送](https://github.com/goindow/mshell/blob/main/example/pushkey.png)
