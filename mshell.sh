#!/bin/bash
# 取消通配符解析
set -f

# 版本修订号
# 稳定版为最新 $tag，开发版为最新 $tag-dev
# revision=1.2.0-dev
revision=1.2.0

# 工作路径，可更换
path=~
# 工作区
workspace=${path/%\//}/.mshell
# session 数据表 - json
session_list_file=$workspace/session.list
# session 缓存 - list|ls
session_cache_file=$workspace/session.cache

# expect 脚本
ssh_expect_script=$workspace/ssh.exp
scp_expect_script=$workspace/scp.exp
pushkey_expect_script=$workspace/pushkey.exp

function usage() {
  cat << 'EOF'
Usage: mshell COMMAND [ARGS...]

  SSH session management for Mac terminal, while support CentOS, 
  Ubuntu, Darwin, including automatic login, file exchange etc.

Managment Commands:
  add                                Create a new session
  inspect ID                         Display information of a session
  list, ls                           List sessions
  remove ID [ID...], rm              Remove one or more sessions
  update ID                          Update information of a session

Commands:
  pull -f remote:local ID            Pull file or directory from a session
  push -f local:remote ID [ID...]    Push file or directory to one or more sessions
  pushkey ID [ID...]                 Copy the ssh-key to one or more sessions
  ssh ID                             SSH to a session
  version, v                         Show the Mshell version information

EOF
}

# 生成 ssh expect 自动应答脚本
function generate_ssh_expect_script() {
  cat > $ssh_expect_script << 'EOF'
#!/usr/bin/expect
# Usage: ./ssh.exp host port user [pwd]

set host [lindex $argv 0]
set port [lindex $argv 1]
set user [lindex $argv 2]
set pwd  [lindex $argv 3]

spawn ssh -p $port $user@$host

expect {
  # 拒绝连接，端口错误
  "onnection refused" { exit }

  # 密码认证
  "yes/no" { send "yes\r"; exp_continue }
  "assword:" { send "$pwd\r"; exp_continue }
  # 认证失败，权限错误
  "ermission denied" { exit }

  # ssh-key 认证
  # do nothing

  # 不论是 "密码认证" 还是 "ssh-key 认证"，如果登录成功都执行一次如下匹配
  # 登录成功，恢复 LC_CTYPE，保证中文不乱码，父 shell 为了保证 lrzsz 可用，LC_CTYPE 被设置为了 en_US，会导致子 shell(自动登录后) 中文乱码
  "ast login:" { sleep 0.3; send "export LC_CTYPE=zh_CN.UTF-8\r" }
}

interact
EOF
}

# 生成 scp expect 自动应答脚本
function generate_scp_expect_script() {
  cat > $scp_expect_script << 'EOF'
#!/usr/bin/expect
# Usage: ./scp.exp type(push|pull) local remote host port user [pwd]

set timeout -1
set type [lindex $argv 0]
set local [lindex $argv 1]
set remote [lindex $argv 2]
set host [lindex $argv 3]
set port [lindex $argv 4]
set user [lindex $argv 5]
set pwd  [lindex $argv 6]

# spawn 不能识别 shell 通配符，比如 ~，使用 spawn bash -c "shell_commands" 可以识别，并且可以使用 expect 变量
if { "push" == $type } { spawn bash -c "scp -P $port -r $local $user@$host:$remote" }
if { "pull" == $type } { spawn bash -c "scp -P $port -r $user@$host:$remote $local" }

expect {
  # 拒绝连接，端口错误
  "onnection refused" { exit }

  # 密码认证
  "yes/no" { send "yes\r"; exp_continue }
  "assword:" { send "$pwd\r"; exp_continue }
  # 认证失败，权限错误
  "ermission denied" { exit }

  # ssh-key 认证
  # do nothing
}
EOF
}

# 生成 ssh-copy-id expect 自动应答脚本
function generate_pushkey_expect_script() {
  cat > $pushkey_expect_script << 'EOF'
#!/usr/bin/expect
# Usage: ./pushkey.exp host port user [pwd]

set host [lindex $argv 0]
set port [lindex $argv 1]
set user [lindex $argv 2]
set pwd  [lindex $argv 3]

spawn ssh-copy-id -p $port $user@$host

expect {
  # 拒绝连接，端口错误
  "onnection refused" { exit }
  
  # 密码认证
  "yes/no" { send "yes\r"; exp_continue }
  "assword:" { send "$pwd\r"; exp_continue }
  # 认证失败，权限错误
  "ermission denied" { exit }

  # ssh-key 认证
  # do nothing

  # 重复推送
  "already exist" { exit }
}
EOF
}

# 去除两端双引号
# $1 原始字符串
function trim() {
  sed -e 's/^"//;s/"$//' $1
}

# 数组去重
# $@ 数组
function array_uniq() {
  test $# -ne 0 && echo $@ | sed 's/ /\'$'\n/g' | sort | uniq
}

function os() {
  os='Unknown'
  test -x "$(command -v yum)" && os='CentOS'
  test -x "$(command -v apt-get)" && os='Ubuntu'
  test 'Darwin' == $(uname -s) && os='Darwin'
  echo $os
}

# 适配安装器
function adapter() {
  test 'Darwin' == $os && echo "$(command -v brew) install"
  test 'CentOS' == $os && echo "$(command -v yum) install -y"
  test 'Ubuntu' == $os && echo "$(command -v apt-get) install -y"
}

# 通知
# $1 通知类型
# $2 通知内容
function dialog() {
  case $1 in
    fatal) printf '%s\n' "$2" && exit 1;;
    error) printf '%s\n\n%s\n' "$2" 'For more details, see "mshell help".' && exit 1;;
    info)  printf '%s\n' "$2";;
    ok)    echo 'OK.';;
    exit)  echo 'exited.';;
  esac
  exit 0
}

# 操作确认
# $1 操作提示
# $2 错误输入次数，默认 3 次
# @return $?, 0 - 确认操作、1 - 取消操作
function ensure() {
  chances=${2:-3}
  while test $chances -gt 0; do
    read -p "$1, are you sure? [Y/n]: " input
    case $input in
        [yY][eE][sS]|[yY])
          return 0
        ;;
        [nN][oO]|[nN])
          return 1
        ;;
        *)
          chances=$(($chances - 1))
          test $chances -le 0 && echo "exited." && exit 1
          echo "Invalid input...($chances chances left)"
        ;;
    esac
  done
}

# 统计符合条件的 session 数量
# $1 session ID, 模糊匹配
function count_session() {
  test -e $session_list_file && cat $session_list_file | jq .id | grep $1 | wc -l || echo 0
}

# 确认匹配到的 sessions
# $1 调用方命令, 用于提示
# $2+ session IDs
function confirm_sessions() {
  which=${1:-'Operate'} && shift
  echo "Match to $# sessions:"
  for id in $@; do
    session=$(cat $session_list_file | grep $id)
    host=$(echo $session | jq .host | trim)
    name=$(echo $session | jq .name | trim)
    printf "  \033[32m%15s  %s\033[0m\n" $host "$name"
  done
  ensure "$which the above session" || dialog exit
}

# 获取 session 认证信息
# $1 session ID
function get_session_auth_info() {
  session=$(cat $session_list_file | grep $1)
  host=$(echo $session | jq .host | trim)
  port=$(echo $session | jq .port)
  user=$(echo $session | jq .user | trim)
  password=$(echo $session | jq .password | trim)
  auth=($host $port $user $password)
  echo ${auth[@]}
}

# 获取仅匹配一个 session 列表
# $@ session IDs, 模糊匹配
function get_onlyone_session_matched_sessions() {
  list=()
  for id in $@; do
    count=$(count_session $id)
    # 1, 只处理每个参数对应一个 session 的情况（如果某一个参数查询到多个 session，忽略）
    if test $count -eq 1; then
      list+=($(cat $session_list_file | jq .id | grep $id | trim))
    fi
  done
  array_uniq ${list[@]}
}

# 确保仅匹配一个 session
# $1 调用方命令, 用于提示
# $2 session ID, 模糊匹配
function ensure_onlyone_session_matched() {
  test -z $2 && dialog error "\"mshell $1\" requires a session ID as the argument."
  count=$(count_session $2)
  # 0、1+
  if test $count -eq 0; then
    dialog error "No session matched: $2"
  elif test $count -gt 1; then
    dialog error 'Too many sessions matched, please increase the length of ID search information.'
  fi
}

# 确保 expect 相关脚本存在
# $1 expect 脚本简称（$1_expect_script）
function ensure_expect_script_exists() {
  script=$(eval echo '$'$1_expect_script)
  test -x $script -a $script -nt $0 && return
  generate_$1_expect_script && chmod +x $script
}

# 确保 ssh key(rsa) 存在
function ensure_ssh_key_exists() {
  test -e ~/.ssh/id_rsa.pub -a -e ~/.ssh/id_rsa && return
  printf "\n\e[5;33m%s\e[0m\n" "Generate ssh-key..."
  ssh-keygen -b 1024 -t rsa -f ~/.ssh/id_rsa -P ""
}

# 修正 prtinf 打印中英文混合字符串的输出不对齐问题
# $1 原字符串
# $2 期望占用的光标长度
# @return substr，修正后的 prinrf 占位符填充字符串
# @return $?, offset 修正后的 prinrf 占位符长度 %${offset}s
function printf_revision() {
  byte=$(($(echo "$1" | wc -c) - 1))              # 字符串字节数，一个中文 3 个字节
  char=${#1}                                      # 字符串字符数，一个中文 1 个字符
  byte3=$((($byte - $char) / 2))                  # 字符串中三字节（中文）字符数，一个三字节（中文）字符显示时占用两个光标长度
  byte1=$(($char - $byte3))                       # 字符串中单字节（英文）字符数，一个单字节（英文）字符显示时占用一个光标长度
  cursor=$(($byte3 * 2 + byte1))                  # 字符串占用光标长度
  # 字符串全部展示所需的光标长度 <= 期望占用的光标长度
  substr="$1"
  offset=$byte3
  # 字符串全部展示所需的光标长度 > 期望占用的光标长度，需要截取原字符串
  if test $cursor -gt $2; then
    offset=0
    # 截取字符串，从最短字符数（展示的全是三字节（中文）字符）开始检测。截取策略为尽可能的使期望占用的光标长度被占满
    i=$(($2 / 2))
    while test $i -le $char; do
      substr="${1:0:$i}"
      substr_byte=$(($(echo "$substr" | wc -c) - 1))
      substr_char=${#substr}
      substr_byte3=$((($substr_byte - $substr_char) / 2))
      substr_byte1=$(($substr_char - $substr_byte3))
      substr_cursor=$(($substr_byte3 * 2 + substr_byte1))
      if test $substr_cursor -gt $2; then
        # 最后一个字符刚好为三字节（中文）字符，并且比 $2 大一个光标位，必须回退一个三字节（中文）字符（$i-1），又小一个光标位，于是补一个空格对齐
        substr="${1:0:$(($i-1))} " && break
      elif test $substr_cursor -eq $2; then
        break
      fi
      ((i++))
    done
  fi
  echo "$substr" && return $(($2 + $offset))
}

# 构建 list 缓存
function makecache() {
  printf '%-12s      %-24s      %-21s      %-12s      %-s\n' 'ID' 'NAME' 'SOURCE' 'USER' 'REMARKS' > $session_cache_file
  while read line; do
    id=$(echo $line | jq .id | trim)
    name=$(echo $line | jq .name | trim)
    host=$(echo $line | jq .host | trim)
    port=$(echo $line | jq .port)
    user=$(echo $line | jq .user | trim)
    remarks=$(echo $line | jq .remarks | trim)
    hostport="$host:$port"
    # 修正 prtinf 打印中英文混合字符串的输出不对齐问题
    name_substr=$(printf_revision "$name" 24)
    name_offset=$?
    user_substr=$(printf_revision "$user" 12)
    user_offset=$?
    printf "%-12s      %-${name_offset}s      %-21s      %-${user_offset}s      %-s\n" "${id:0:12}" "${name_substr}" "$hostport" "$user_substr" "$remarks" >> $session_cache_file
  done < $session_list_file
}

# 构建 session
# $1 session ID, 更新操作的时候带上, 不会修改 session ID; 新增操作不需要
function build_session() {
  ipv4="^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){2}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$"
  # name
  read -p "Input session name: " name
  while test -z "$name"; do read -p "Input session name(Required): " name; done
  # host
  read -p "Input session host: " host
  while [[ ! "$host" =~ $ipv4 ]]; do read -p "Input session host(Invalid input): " host; done
  # port, default 22
  read -p "Input session port<Enter, 22>: " port
  port=${port:-22}
  while [[ ! "$port" =~ ^[0-9]+$ ]] || [ $port -gt 65535 ]; do read -p "Input session port(Invalid input): " port; done
  # user, default root
  read -p "Input session user<Enter, root>: " user
  user=${user:-root}
  # password, ssh-key 认证模式无需密码
  read -p "Input session password: " password
  # remarks
  read -p "Input session remarks: " remarks
  # id, 更新操作的时候带上, 不会修改 session ID; 新增操作不需要
  id=$(test -z $1 && echo -n "$host:$port:$RANDOM" | sha1sum | cut -d ' ' -f1 || echo $1)
  # session
  printf '{"id":"%s", "name":"%s", "host":"%s", "port":%s, "user":"%s", "password":"%s", "remarks":"%s"}\n' $id "$name" $host $port "$user" "$password" "$remarks"
}

# 查看 session 列表
function list_session() {
  test $session_list_file -nt $session_cache_file && makecache
  test -e $session_cache_file && cat $session_cache_file || dialog info "Session list is empty, please add session first."
}

# 查看 session 详情
# $1 session ID, 模糊匹配
function inspect_session() {
  ensure_onlyone_session_matched inspect $1 && cat $session_list_file | grep $1 | jq .
}

# 更新 session
# $1 session ID, 模糊匹配
function update_session() {
  ensure_onlyone_session_matched update $1
  id=$(cat $session_list_file | jq .id | grep $1 | trim)
  session=$(build_session $id)
  # sed -i, Unix(Darwin) 和 Linux 有差异, 做兼容处理
  test 'Darwin' == $os && sed -i "" "s/.*$id.*/$session/" $session_list_file || sed -i "s/.*$id.*/$session/" $session_list_file
  dialog ok
}

# 批量删除 session
# $@ session IDs, 模糊匹配
function remove_sessions() {
  test $# -eq 0 && dialog error '"mshell remove|rm" requires at least one session ID as the argument.'
  # 待处理集合
  list=($(get_onlyone_session_matched_sessions $@))
  # 提示确认
  test ${#list[@]} -gt 0 && confirm_sessions "Remove" ${list[@]} || dialog error "No session matched: $*"
  # 删除
  for id in ${list[@]}; do
    # sed -i, Unix(Darwin) 和 Linux 有差异, 做兼容处理
    test 'Darwin' == $os && sed -i "" "/.*$id.*/d" $session_list_file || sed -i "/.*$id.*/d" $session_list_file
  done
  dialog ok
}

# 新增 session
function add_session() {
  build_session >> $session_list_file && dialog ok
}

# 登录 session
function ssh_to_session() {
  ensure_onlyone_session_matched ssh $1
  ensure_expect_script_exists ssh
  # 解决使用 expect 脚本登录后 lrzsz 失效问题，在 expect 脚本中恢复子 shell 的 LC_CTYPE=zh_CN.UTF-8
  export LC_CTYPE=en_US
  # Usage: ./ssh.exp host port user [password]
  $ssh_expect_script $(get_session_auth_info $1)
}

# 拉取文件/目录
# mshell pull -f remote:local id
function pull_from_session() {
  while getopts ':f:' options; do
    case $options in
      f)
        file=$OPTARG
      ;;
    esac
  done
  shift $(($OPTIND - 1))
  # 参数校验，-f remote:local
  test -z $file && dialog error "Requires an argument -f, like \"mshell pull -f remote:local id\"."
  # ${files[0]} - remote, ${files[1]} - local
  files=(${file/:/ })
  test ${#files[@]} -le 1 && dialog error "Invalid argument -f, like \"mshell pull -f remote:local id\"."
  # 准备
  ensure_onlyone_session_matched pull $1
  ensure_expect_script_exists scp
  # 拉取
  # Usage: ./scp.exp type(push|pull) local remote host port user [pwd]
  $scp_expect_script pull ${files[1]} ${files[0]} $(get_session_auth_info $1)
}

# 批量推送文件/目录
# mshell push -f local:remote ids...
function push_to_sessions() {
  while getopts ':f:' options; do
    case $options in
      f)
        file=$OPTARG
      ;;
    esac
  done
  shift $(($OPTIND - 1))
  # 参数校验，-f local:remote
  test -z $file && dialog error "Requires an argument -f, like \"mshell push -f local:remote ids...\"."
  # ${files[0]} - local, ${files[1]} - remote
  files=(${file/:/ })
  test ${#files[@]} -le 1 && dialog error "Invalid argument -f, like \"mshell push -f local:remote ids...\"."
  # 参数校验，session ids
  test $# -eq 0 && dialog error '"mshell push" requires at least one session ID as the argument.'
  # 待处理集合
  list=($(get_onlyone_session_matched_sessions $@))
  # 提示确认
  test ${#list[@]} -gt 0 && confirm_sessions "Push ${files[0]} to" ${list[@]} || dialog error "No session matched: $*"
  # 准备
  ensure_expect_script_exists scp
  # 推送
  for id in ${list[@]}; do
    session=($(get_session_auth_info $id))
    printf "\n\e[5;33m%s\e[0m\n" "Push to ${session[0]}..."
    # Usage: ./scp.exp type(push|pull) local remote host port user [pwd]
    $scp_expect_script push ${files[@]} ${session[@]}
  done
}

# 批量推送 ssh key
function pushkey_to_sessions() {
  test $# -eq 0 && dialog error '"mshell pushkey" requires at least one session ID as the argument.'
  # 待处理集合
  list=($(get_onlyone_session_matched_sessions $@))
  # 提示确认
  test ${#list[@]} -gt 0 && confirm_sessions "Push ssh-key to" ${list[@]} || dialog error "No session matched: $*"
  # 准备
  ensure_ssh_key_exists
  ensure_expect_script_exists pushkey
  # 推送 ssh-key
  for id in ${list[@]}; do
    session=($(get_session_auth_info $id))
    printf "\n\e[5;33m%s\e[0m\n" "Push ssh-key to ${session[0]}..."
    # Usage: ./pushkey.exp host port user [password]
    $pushkey_expect_script ${session[@]}
  done
}

function install_expect() {
  $(adapter) expect
}

function install_jq() {
  $(adapter) jq
}

function install_sha1sum() {
  # CentOS、Ubuntu 无需安装
  test 'Darwin' == $os && brew install md5sha1sum
}

function install_brew() {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  test ! -x "$(command -v brew)" && dialog fatal "Failed to install brew, please manually install dependencies first. If already installed, add to the PATH."
  brew update
}

function check_dependencies() {
  dependencies=(brew sha1sum jq expect)
  test 'Darwin' != $os && unset dependencies[0]
  # 待安装集合
  for dependence in ${dependencies[@]}; do
    test ! -x "$(command -v $dependence)" && list+=($dependence)
  done
  test ${#list[@]} -eq 0 && return
  # 缺失必要依赖
  echo -e "Lack of necessary dependencies:\n\n \033[33m${list[@]}\033[0m\n"
  test 'Unknown' == $os && dialog fatal "Unknown os, please manually install dependencies first. If already installed, add to the PATH."
  # 用户确认
  ensure 'Install the above dependencies' || dialog exit
  # 安装
  for dependence in ${list[@]}; do
    install_$dependence
  done
}

function check_workspace() {
  test -d $workspace && return
  mkdir $workspace &> /dev/null || dialog fatal "Workspace($workspace) created failed, please check directory permissions."
}

function init() {
  check_dependencies
  check_workspace
}

# main
os=$(os)
init
case $1 in
  add)       add_session;;
  remove|rm) shift && remove_sessions $@;;
  update)    update_session $2;;
  inspect)   inspect_session $2;;
  list|ls)   list_session;;
  ssh)       ssh_to_session $2;;
  pull)      shift && pull_from_session $@;;
  push)      shift && push_to_sessions $@;;
  pushkey)   shift && pushkey_to_sessions $@;;
  version|v) echo $revision;;
  *)         usage;;
esac
