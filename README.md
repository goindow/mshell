# mshell
终端 SSH 会话管理，同时支持CentOS，Ubuntu，Darwin，包括会话的增删改查、自动登录、公钥推送等功能

## 说明
- 该工具主要争对 Mac 用户，以避免安装多个 Terminal，推荐使用**iTerm2+该工具**，则可同时支持 lrzsz 及 ssh 会话管理
- 同时也支持常用的 OS(CentOS、Ubuntu)，可用作跳板机的会话管理

## 支持的 OS
- Darwin
- CentOS
- Ubuntu

## 依赖说明
- sha1sum，用于生成 Session ID
- jq，用于 JSON 操作，Session 数据以 JSON 格式存储
- expect，用于支持自动登录

## 使用
- Managment Commands:
  - mshell add                               Create one session
  - mshell remove <ID[,...]>                 Remove one or more sessions
  -        rm                                Alias for remove
  - mshell update <ID>                       Update information of one session
  - mshell inspect <ID>                      Return information of one or more sessions
  - mshell list                              List sessions
  -        ls                                Alias for lis
- Commands:
  - mshell ssh <ID>                          SSH to session, automatical login
