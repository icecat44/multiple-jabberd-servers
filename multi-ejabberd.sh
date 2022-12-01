#!/bin/bash
############################# SetUp zone #############################################################
# Пароль для созданных пользователей:
def_pass="pa55worD"
# Jabberd port:
japort="5222"
########################################################################################################
###
### Укажите последние актеты свободных IP адресов на которых будут запускать отдельные сервесы Jabber.
### обратите внимание, на хосте должны быть прописаны алиасы в настройках сети.
declare -a arr1=(221 222 223 224 225)
###
########################################################################################################
WORKDIR="/opt/jabber"
if [ "$EUID" -ne 0 ]; then  echo -e "\033[6m\033[41m\033[1m   !!!!!    Используйте sudo $0    !!!!!   \033[0m ";  exit 1; fi
if ! [ -d $WORKDIR/conf/ ]; then
mkdir -p $WORKDIR/conf
fi
        clear
        echo -e "Установка сервисов Jabber.\n"
        echo "Выберите опцию для выполнения:"
        echo "   1. Добавить сервер"
        echo "   2. Список запущенных серверов"
        echo "   3. Удалить сервер и отчистить"
        echo "   4. Удалить все и отчистить"
        echo "   5. Выход"
        read -p "Введите номер опции: " option
        until [[ "$option" =~ ^[1-5]$ ]]; do
                echo "$option: Неверный ввод."
                read -p "Введите номер опции: " option
        done
        if=ens160
        net=$(ip a s dev $if |grep "inet " | head -n1 | awk {'print $2'} | awk -F "." {'print $1"."$2"."$3"."'})
        case "$option" in
                1)
                        last_n=$(ss -nlpt | grep $japort | awk {'print $4'} | awk -F "." {'print $4'} | awk -F ":" {'print $1'})
                        declare -a arr2=($last_n)
                        arr3=$(echo ${arr1[@]} $last_n | tr ' ' '\n' | sort | uniq -u | tr -s '\r\n' ' ')
                        free=$(echo $arr3 | awk '{print $1}')
                        freeip=$(echo $net$free)
                        if [ -z $free ] ; then
                                clear
                                echo -e "\n\033[31mОШИБКА!\n\n\033[33mНет свободных IP адресов для нового сервера. \nУдалите один или несколько ненужных серверов и попробуйте cнова.\033[0m\n"
                        read -t 15 -p  "Press Enter..."
                        exit
                        fi
# Формируем конфиг для новых контейнеров
cat << EOF > $WORKDIR/conf/ejabberd_$free.yml
###
###              ejabberd configuration file
###
### The parameters used in this configuration file are explained at
###
###       https://docs.ejabberd.im/admin/configuration
###
### The configuration file is written in YAML.
### *******************************************************
### *******           !!! WARNING !!!               *******
### *******     YAML IS INDENTATION SENSITIVE       *******
### ******* MAKE SURE YOU INDENT SECTIONS CORRECTLY *******
### *******************************************************
### Refer to http://en.wikipedia.org/wiki/YAML for the brief description.
###

hosts:
  - $freeip

loglevel: info

ca_file: /home/ejabberd/conf/cacert.pem

certfiles:
  - /home/ejabberd/conf/server.pem

## If you already have certificates, list them here
# certfiles:
#  - /etc/letsencrypt/live/domain.tld/fullchain.pem
#  - /etc/letsencrypt/live/domain.tld/privkey.pem

listen:
  -
    port: 5222
    ip: "::"
    module: ejabberd_c2s
    max_stanza_size: 262144
    shaper: c2s_shaper
    access: c2s
    starttls_required: true
  -
    port: 5223
    ip: "::"
    tls: true
    module: ejabberd_c2s
    max_stanza_size: 262144
    shaper: c2s_shaper
    access: c2s
    starttls_required: true
  -
    port: 5269
    ip: "::"
    module: ejabberd_s2s_in
    max_stanza_size: 524288
  -
    port: 5443
    ip: "::"
    module: ejabberd_http
    tls: true
    request_handlers:
      /admin: ejabberd_web_admin
      /api: mod_http_api
      /bosh: mod_bosh
      /captcha: ejabberd_captcha
      /upload: mod_http_upload
      /ws: ejabberd_http_ws
  -
    port: 5280
    ip: "::"
    module: ejabberd_http
    request_handlers:
      /admin: ejabberd_web_admin
      /.well-known/acme-challenge: ejabberd_acme
  -
    port: 3478
    ip: "::"
    transport: udp
    module: ejabberd_stun
    use_turn: true
    ## The server's public IPv4 address:
    # turn_ipv4_address: "203.0.113.3"
    ## The server's public IPv6 address:
    # turn_ipv6_address: "2001:db8::3"
  -
    port: 1883
    ip: "::"
    module: mod_mqtt
    backlog: 1000

s2s_use_starttls: optional

acl:
  admin:
    user: admin@$freeip
  local:
    user_regexp: ""
  loopback:
    ip:
      - 127.0.0.0/8
      - 0.0.0.0/0
      - ::1/128

access_rules:
  local:
    allow: local
  c2s:
    deny: blocked
    allow: all
  announce:
    allow: admin
  configure:
    allow: admin
  muc_create:
    allow: local
  pubsub_createnode:
    allow: local
  trusted_network:
    allow: loopback

api_permissions:
  "console commands":
    from:
      - ejabberd_ctl
    who: all
    what: "*"
  "admin access":
    who:
      access:
        allow:
          - acl: loopback
          - acl: admin
      oauth:
        scope: "ejabberd:admin"
        access:
          allow:
            - acl: loopback
            - acl: admin
    what:
      - "*"
      - "!stop"
      - "!start"
  "public commands":
    who:
      ip: 127.0.0.1/8
    what:
      - status
      - connected_users_number

shaper:
  normal:
    rate: 3000
    burst_size: 20000
  fast: 100000

shaper_rules:
  max_user_sessions: 10
  max_user_offline_messages:
    5000: admin
    100: all
  c2s_shaper:
    none: admin
    normal: all
  s2s_shaper: fast

modules:
  mod_adhoc: {}
  mod_admin_extra: {}
  mod_announce:
    access: announce
  mod_avatar: {}
  mod_blocking: {}
  mod_bosh: {}
  mod_caps: {}
  mod_carboncopy: {}
  mod_client_state: {}
  mod_configure: {}
  mod_disco: {}
  mod_fail2ban: {}
  mod_http_api: {}
  mod_http_upload:
    put_url: https://@HOST@:5443/upload
    custom_headers:
      "Access-Control-Allow-Origin": "https://@HOST@"
      "Access-Control-Allow-Methods": "GET,HEAD,PUT,OPTIONS"
      "Access-Control-Allow-Headers": "Content-Type"
  mod_last: {}
  mod_mam:
    ## Mnesia is limited to 2GB, better to use an SQL backend
    ## For small servers SQLite is a good fit and is very easy
    ## to configure. Uncomment this when you have SQL configured:
    ## db_type: sql
    assume_mam_usage: true
    default: always
  mod_mqtt: {}
  mod_muc:
    access:
      - allow
    access_admin:
      - allow: admin
    access_create: muc_create
    access_persistent: muc_create
    access_mam:
      - allow
    default_room_options:
      mam: true
  mod_muc_admin: {}
  mod_offline:
    access_max_user_messages: max_user_offline_messages
  mod_ping: {}
  mod_privacy: {}
  mod_private: {}
  mod_proxy65:
    access: local
    max_connections: 5
  mod_pubsub:
    access_createnode: pubsub_createnode
    plugins:
      - flat
      - pep
    force_node_config:
      ## Avoid buggy clients to make their bookmarks public
      storage:bookmarks:
        access_model: whitelist
  mod_push: {}
  mod_push_keepalive: {}
  mod_register:
    ## Only accept registration requests from the "trusted"
    ## network (see access_rules section above).
    ## Think twice before enabling registration from any
    ## address. See the Jabber SPAM Manifesto for details:
    ## https://github.com/ge0rg/jabber-spam-fighting-manifesto
    ip_access: trusted_network
  mod_roster:
    versioning: true
  mod_s2s_dialback: {}
  mod_shared_roster: {}
  mod_stream_mgmt:
    resend_on_timeout: if_offline
  mod_stun_disco: {}
  mod_vcard: {}
  mod_vcard_xupdate: {}
  mod_version:
    show_os: false

### Local Variables:
### mode: yaml
### End:
### vim: set filetype=yaml tabstop=8
EOF
docker run --name $freeip -v $WORKDIR/conf/ejabberd_$free.yml:/home/ejabberd/conf/ejabberd.yml  -it -d -p $freeip:5222:5222 -p $freeip:5280:5280 -p $freeip:5443:5443 -p $freeip:5223:5223 -p $freeip:5269:5269 -p $freeip:3478:3478 -p $freeip:1883:1883  --init ejabberd/ecs:22.10 > /dev/null 2>&1
                        clear
                                tput civis
                                spinner() {
                                    local i sp n
                                ###### Select Slinner style:
                                #    sp='/-\|'
                                #    sp='⣾⣽⣻⢿⡿⣟⣯⣷'
                                    sp='⠁⠂⠄⡀⢀⠠⠐⠈'
                                #    sp='←↖↑↗→↘↓↙'
                                #    sp='┤┘┴└├┌┬┐'
                                ###########################
                                    n=${#sp}
                                    printf ' '
                                    while sleep 0.1; do
                                        printf "%s\b" "${sp:i++%n:1}"
                                    done
                                }
                                echo -ne "\033[32mНастраиваем новый сервер. Oбработка... "
                                spinner &
                                sleep 10
                                tput cnorm
                                kill "$!"
                        clear
                        echo -e "Новый сервер создан успешно!\n\n\033[36mВиртуальные хосты на сервере:\033[37m"
                        docker exec $freeip bin/ejabberdctl registered_vhosts
                        echo -e "\n\033[36mПользователи:\033[37m"
                        docker exec $freeip bin/ejabberdctl register admin $freeip $def_pass
                        docker exec $freeip bin/ejabberdctl register user1 $freeip $def_pass
                        echo
                        tput civis
                                printer() {
                                    local i sp1 n
                                    sp1='Скопируйте ссылку в буфер обмена.                                                                                                                                                                                                                                                                              '
                                    n=${#sp1}
                                    printf ' '
                                    while sleep 0.05; do
                                        printf "%s" "${sp1:i++%n:1}"
                                    done
                                }
                                echo -ne "\033[32mПанель управления новым сервером \033[37mhttp://$freeip:5280/admin/ \033[32mпользователь admin. "
                                printer &
                                sleep 15
                                kill "$!"
                        echo  -e "\033[0m"
                        tput cnorm
                        $0
                ;;
                2)
                        clear
                        echo -e "Работающие в настоящий момент серверы Jabber: \n \033[33m"
                        docker ps -a -q -f name="$net" --format "table {{.Names}}\t{{.CreatedAt}}\t{{.State}}"
                        echo -e "\033[0m"
                        read -t 10 -p "Press Enter..."
                        $0
                ;;
                3)
                        clear
                        echo "Работающие в настоящий момент серверы Jabber"
                                docker ps -a -f name="$net" --format "table {{.ID}}\t{{.Names}}"
                        echo 
                        read -p "Введите первые два символа поля \"CONTAINER ID\" для удаления: " jaid
                        echo -e "\033[31m"
                        read -p "Удалить $jaid? [y/N]: " remove
                        until [[ "$remove" =~ ^[yYnN]*$ ]]; do
                                echo "$remove: invalid selection."
                                read -p "Удалить $jaid? [y/N]: " remove
                        done
                        echo -e "\033[0m"
                        if [[ "$remove" =~ ^[yY]$ ]]; then
                        docker rm -f -v $jaid
                        echo -e "Сервер $jaid удален.\033[0m"
                        read -t 15 -p  "Press Enter..."
                        else 
                        $0
                        fi
                        $0
                ;;
                4)
                        clear
                        echo -e "\033[31m"
                        read -p "Удалить Все серверы? [y/N]: " remove
                        until [[ "$remove" =~ ^[yYnN]*$ ]]; do
                                echo "$remove: invalid selection."
                                read -p "Удалить Все серверы [y/N]: " remove
                        echo -e "\033[0m"
                        done
                        if [[ "$remove" =~ ^[yY]$ ]]; then
                        docker rm -f -v $(docker ps -a -f name=$net -q) > /dev/null 2>&1
                        clear
                        echo -e "Все серверы удалены! \n \033[0m"
                        echo -e "\033[0m"
                        read -t 15 -p  "Press Enter..."
                        else 
                        echo -e "\033[0m"
                        $0
                        fi
                        $0
                ;;
                5)
                        exit
                ;;
        esac
