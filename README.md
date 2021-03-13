# mshell
终端 SSH 会话管理，同时支持CentOS，Ubuntu，Darwin，包括会话的增删改查、自动登录、公钥推送、会话分组等功能

## 说明
- 该工具主要争对 Mac 用户，以避免安装多个 Terminal，推荐使用**iTerm2+该工具**，则可同时支持 lrzsz 及 ssh 会话管理
- 同时也支持常用的 OS(CentOS、Ubuntu)，可用作跳板机的会话管理

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
  - 如果嫌 mshell add/update 交互式操作麻烦，可以手动编辑该文件，缓存会自动更新，也可以手动调整 session 排序等，切记不要破坏数据结构
  - 如果需要更换设备或重装系统，可将该文件复制到新设备上，即可完成迁移
  - 注意！不要在共享设备上使用该工具（如若使用，切记销毁该文件），密码及相关数据都是明文存储
- session.cache，mshell list 缓存
- autologin.exp，expect 自动登录脚本

## 使用
```shell
Usage: mshell COMMAND [ARGS...]

  SSH session management for Mac terminal, while support CentOS,
  Ubuntu, Darwin, including automatic login, public key push etc.

Managment Commands:
  mshell add                               Create one session

  mshell remove <ID[,...]>                 Remove one or more sessions
         rm                                Alias for remove

  mshell update <ID>                       Update information of one session

  mshell inspect <ID>                      Return information of one or more sessions
 
  mshell list                              List sessions
         ls                                Alias for list

Commands:
  mshell ssh <ID>                          SSH to session, automatical login
```

## 示例
![测试报告](https://github.com/goindow/mshell/blob/master/example/example.png)

## todo:
- 公钥推送
- Session 分组
