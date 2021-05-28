#!/bin/bash
# 解决使用 expect 脚本登录后，lrzsz 是失效问题
export LC_CTYPE=en_US

# 工作路径，可更换
path=~

# 工作区
workspace=${path/%\//}/.mshell
# session 数据表, json
session_list_file=$workspace/session.list
# session 缓存 - list|ls
session_cache_file=$workspace/session.cache
# expect 自动登录脚本
autologin_expect_file=$workspace/autologin.exp

ipv4="^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){2}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$"

function usage() {
  cat << 'EOF'
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
  
EOF
}

function os() {
  os='Unknown'
  test -x "$(command -v yum)" && os='CentOS'
  test -x "$(command -v apt-get)" && os='Ubuntu'
  test 'Darwin' == $(uname -s) && os='Darwin'
  echo $os
}

function adapter() {
  test 'Darwin' == $os && echo "$(command -v brew) install"
  test 'CentOS' == $os && echo "$(command -v yum) install -y"
  test 'Ubuntu' == $os && echo "$(command -v apt-get) install -y"
}

# 去除两端双引号
# $1 原始字符串
function trim() {
  sed -e 's/^"//;s/"$//' $1
}

# 数组去重
# $@ 数组元素
function array_uniq() {
  test $# -ne 0 && echo $@ | sed 's/ /\'$'\n/g' | uniq
}

# 通知
# $1 通知类型
# $2 通知内容
function dialog() {
  case $1 in
    fatal)
      printf '%s\n' "$2" && exit 1
    ;;
    error)
      printf '%s\n\n%s\n' "$2" 'For more details, see "mshell help".' && exit 1
    ;;
    info)
      printf '%s\n\n%s\n' "$2" 'For more details, see "mshell help".'
    ;;
    ok)
      echo 'OK.'
    ;;
    exit)
      echo 'exited.'
  esac
  exit 0
}

# 操作确认
# $1 操作提示
# $2 错误输入次数，默认 3 次
# @return $?, 0 - 确认操作、1 - 取消操作
function ensure() {
  flag=${2:-3}
  while test $flag -gt 0; do
    read -p "$1, are you sure? [Y/n]: " input
    case $input in
        [yY][eE][sS]|[yY])
          return 0
        ;;
        [nN][oO]|[nN])
          return 1
        ;;
        *)
          flag=$(($flag - 1))
          test $flag -le 0 && echo "exited." && exit 1
          echo "Invalid input...($flag chances left)"
        ;;
    esac
  done
}

# 计数 - 符合条件的 session 数量
# $1 session ID, 模糊匹配
function count_session() {
  test -e $session_list_file && cat $session_list_file | jq .id | grep $1 | wc -l || return 0
}

# 确保 - 仅匹配一个 session
# $1 调用方命令, 用于提示
# $2 session ID, 模糊匹配
function ensure_onlyone_session_matched() {
  test -z $2 && dialog error "\"$1\" requires a session ID as the argument."
  count=$(count_session $2)
  # 0、1+
  if test $count -eq 0; then
    dialog error "No matched session: $2"
  elif test $count -gt 1; then
    dialog error 'Too many sessions matched, please increase the length of ID search information.'
  fi
}

# 生成 - 自动登录脚本
function generate_autologin_script() {
  cat > $autologin_expect_file << 'EOF'
#!/usr/bin/expect
# Usage: ./autologin.exp host port user [password]

set host [lindex $argv 0]
set port [lindex $argv 1]
set user [lindex $argv 2]
set pwd  [lindex $argv 3]

spawn ssh -p $port $user@$host

expect {
  "yes/no" { send "yes\r"; exp_continue }
  "assword:" { send "$pwd\r" }
}

interact
EOF
}

# 确保 - 自动登录脚本存在
function ensure_autologin_script_exists() {
  test -x $autologin_expect_file && return
  generate_autologin_script && chmod +x $autologin_expect_file
}

# 计算字符串中包含的中文个数, the number of chinese chars in a string
# printf 中 %ns, 当输入中包含长字节字符串(中文)时, n 计算的是字符长度, 导致对齐失败, 我们希望一个长字节字符串算作一个长度
# $1 原始字符串
function ncc() {
  char_length=$(($(echo $1 | wc -c) - 1))         # 一个中文3个 char 长度
  unicode_length=${#1}                            # 一个中文1个 unicode 长
  echo $((($char_length - $unicode_length) / 2))  # 一个中文两种计算方式的差值为 2（恰好屏幕中显示中文占用2个屏幕单位宽度）
}

# 屏幕输出包含中文的字符串的偏移量, n+offset 才是屏幕中包含中文字符串 printf 的正确长度
# $1 原始字符串
# $2 printf 格式化输出字符数 - "printf '%ns'" 中的 n
function printf_offset() {
  ncc=$(ncc $1)
  ncc_max=$(($2/2))
  offset=0                                              # $ncc == 0 || $ncc > $ncc_max
  test 0 -lt $ncc -a $ncc -le $ncc_max && offset=$ncc   # 0 < $ncc <= $ncc_max
  echo $offset
}

# 屏幕输出包含中文的字符串的切片长度, ${string:0:slice} 才是屏幕中在 n 限制下的正确字符串的最大切片长度, 不超过 n
# $1 原始字符串
# $2 printf 格式化输出字符数 - "printf '%ns'" 中的 n
function printf_slice() {
  ncc=$(ncc $1)
  ncc_max=$(($2/2))
  slice=$2                                              # $ncc == 0
  if test 0 -lt $ncc -a $ncc -le $ncc_max; then         # 0 < $ncc <= $ncc_max
    slice=$(($2-$ncc))
  elif test $ncc_max -lt $ncc; then                     # $ncc > $ncc_max
    slice=$(($2-$ncc_max))
  fi
  echo $slice
}

# 构建 list 缓存
function makecache() {
  printf '' > $session_cache_file
  printf '%-12s      %-24s      %-21s      %-12s      %-s\n' 'ID' 'NAME' 'SOURCE' 'USER' 'REMARKS' >> $session_cache_file
  while read line; do
    id=$(echo $line | jq .id | trim)
    name=$(echo $line | jq .name | trim)
    host=$(echo $line | jq .host | trim)
    port=$(echo $line | jq .port)
    user=$(echo $line | jq .user | trim)
    remarks=$(echo $line | jq .remarks | trim)
    hostport="$host:$port"
    # 包含中文的字符串打印错位修正, offset、slice 计算
    name_offset=$(printf_offset "$name" 24)
    name_slice=$(printf_slice "$name" 24)
    printf "%-12s      %-$((24+$name_offset))s      %-21s      %-12s      %-s\n" "${id:0:12}" "${name:0:$name_slice}" "${hostport:0:24}" "${user:0:12}" "$remarks" >> $session_cache_file
  done < $session_list_file
}

# 构建 session
# $1 session ID, 更新操作的时候带上, 不会修改 session ID; 新增操作不需要
function build_session() {
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
  # password, no password needed by secret key
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
  # 更新缓存, -nt 如果左边文件比右边文件新, 则为真
  test $session_list_file -nt $session_cache_file && makecache
  test -e $session_cache_file && cat $session_cache_file || dialog info "Session list is empty, please add session first."
}

# 查看 session 详情
# $1 session ID, 模糊匹配
function inspect_session() {
  test -z $1 && dialog error '"mshell inspect" requires a session ID as the argument.' 
  count=$(count_session $1)
  # 0
  test $count -eq 0 && dialog error "No matched session: $1"
  # 0+
  for id in $(cat $session_list_file | jq .id | grep $1); do
    cat $session_list_file | grep $id | jq .
  done
}

# 更新 session
# $1 session ID, 模糊匹配
function update_session() {
  ensure_onlyone_session_matched 'mshell update' $1
  id=$(cat $session_list_file | jq .id | grep $1 | trim)
  session=$(build_session $id)
  # sed -i, Unix(Darwin) 和 Linux 有差异, 做兼容处理
  test 'Darwin' == $os && sed -i "" "s/.*$id.*/$session/" $session_list_file || sed -i "s/.*$id.*/$session/" $session_list_file
  dialog ok
}

# 删除 session
# $@ session IDs, 模糊匹配, 可以批量删除
function remove_session() {
  test $# -eq 0 && dialog error '"mshell remove|rm" requires at least one session ID as the argument.'
  # 待删除集合
  list=()
  for id in $@; do
    count=$(count_session $id)
    # 1, 只处理每个参数对应一个 session 的情况（如果某一个参数查询到多个 session，忽略）
    if test $count -eq 1; then
      list+=($(cat $session_list_file | jq .id | grep $id | trim))      
    fi
  done
  test ${#list[@]} -eq 0 && dialog error "No matched session: $*"
  # 匹配到 session
  list=($(array_uniq ${list[@]}))
  echo "Match to ${#list[@]} sessions:"
  for id in ${list[@]}; do
    cat $session_list_file | grep $id | jq .
  done
  # 用户确认
  ensure 'Remove the above session' || dialog exit
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
function ssh_session() {
  ensure_onlyone_session_matched 'mshell ssh' $1
  ensure_autologin_script_exists
  session=$(cat $session_list_file | grep $1)
  host=$(echo $session | jq .host | trim)
  port=$(echo $session | jq .port)
  user=$(echo $session | jq .user | trim)
  password=$(echo $session | jq .password | trim)
  # Usage: ./autologin.exp host port user [password]
  $autologin_expect_file $host $port $user $password
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
  add)
    add_session
  ;;
  remove|rm)
    shift && remove_session $@
  ;;
  update)
    update_session $2
  ;;
  inspect)
    inspect_session $2
  ;;
  list|ls)
    list_session
  ;;
  ssh)
    ssh_session $2
  ;;
  *)
    usage
  ;;
esac
