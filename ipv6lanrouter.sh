#!/bin/bash
set -eo pipefail

function message(){
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@"
}

# Global Variable
CHECK=${CHECK:-3}
LAN_MODE=${LAN_MODE:-docker}
PREFIXLEN="${PREFIXLEN:-60}"
MTU=${MTU:-0}
RDNSS=($(echo "$RDNSS" | sed -e 's/;/ /g'))
EXCLUDE_SUB=($(echo "$EXCLUDE_SUB" | sed -e 's/;/ /g'))
EXCLUDE_NUM1=($(echo "$EXCLUDE_NUM1" | sed -e 's/;/ /g'))
EXCLUDE_NUM2=($(echo "$EXCLUDE_NUM2" | sed -e 's/;/ /g'))

echo "======================================== IPv6 LAN Router ==========================================="
message "INFO: [CHECK]: ${CHECK}"
if [[ "$PREFIXLEN" == "64" ]]; then
  message "INFO: [LAN_MODE]: ${LAN_MODE}"
fi
message "INFO: [PREFIXLEN]: ${PREFIXLEN}"
message "INFO: [MTU]: ${MTU}"
message "INFO: [RDNSS]: ${RDNSS[@]}"
message "INFO: [EXCLUDE_SUB]: ${EXCLUDE_SUB[@]}"
message "INFO: [EXCLUDE_NUM1]: ${EXCLUDE_NUM1[@]}"
message "INFO: [EXCLUDE_NUM2]: ${EXCLUDE_NUM2[@]}"

# Subnet Address Pool
sub0_7=(0 1 2 3 4 5 6 7)
sub8_f=(8 9 a b c d e f)
sub0_f=(${sub0_7[@]} ${sub8_f[@]})
for a1 in ${sub0_7[@]}; do
  for b1 in ${sub0_f[@]}; do
    sub00_7f=(${sub00_7f[@]} ${a1}${b1})
  done
done
for a2 in ${sub8_f[@]}; do
  for b2 in ${sub0_f[@]}; do
    sub80_ff=(${sub80_ff[@]} ${a2}${b2})
  done
done
for a3 in ${sub0_f[@]}; do
  for b3 in ${sub0_f[@]}; do
    sub00_ff=(${sub00_ff[@]} ${a3}${b3})
  done
done
# Exclude Subnet Address
for a4 in ${EXCLUDE_NUM1[@]}; do
  for b4 in ${EXCLUDE_NUM2[@]}; do
    EXCLUDE_SUB=(${EXCLUDE_SUB[@]} ${a4}${b4})
  done
done
if [[ "${#EXCLUDE_SUB[@]}" != "0" ]]; then
  for a5 in ${EXCLUDE_SUB[@]}; do
    if [[ "$PREFIXLEN" == "56" ]]; then
      for ((i=0;i<${#sub00_ff[@]};i++)); do
        if [[ "$a5" == "${sub00_ff[$i]}" ]]; then
          sub00_ff=(${sub00_ff[@]:0:$i} ${sub00_ff[@]:$i+1})
        fi
      done
    elif [[ "$PREFIXLEN" == "58" ]]; then
      for ((i=0;i<${#sub00_7f[@]};i++)); do
        if [[ "$a5" == "${sub00_7f[$i]}" ]]; then
          sub00_7f=(${sub00_7f[@]:0:$i} ${sub00_7f[@]:$i+1})
        fi
        if [[ "$a5" == "${sub80_ff[$i]}" ]]; then
          sub80_ff=(${sub80_ff[@]:0:$i} ${sub80_ff[@]:$i+1})
        fi
      done
    elif [[ "$PREFIXLEN" == "60" ]]; then
      for ((i=0;i<${#sub0_f[@]};i++)); do
        if [[ "$a5" == "${sub0_f[$i]}" ]]; then
          sub0_f=(${sub0_f[@]:0:$i} ${sub0_f[@]:$i+1})
        fi
      done
    elif [[ "$PREFIXLEN" == "62" ]]; then
      for ((i=0;i<${#sub0_7[@]};i++)); do
        if [[ "$a5" == "${sub0_7[$i]}" ]]; then
          sub0_7=(${sub0_7[@]:0:$i} ${sub0_7[@]:$i+1})
        fi
        if [[ "$a5" == "${sub8_f[$i]}" ]]; then
          sub8_f=(${sub8_f[@]:0:$i} ${sub8_f[@]:$i+1})
        fi
      done
    fi
  done
  message "INFO: [EXCLUDE]: [${EXCLUDE_SUB[@]}]"
fi

# Get Interfaces
NET=($(ip -j link show | jq -r '.[] | select(.ifname != "lo") | .ifname'))
if [[ ${#NET[@]} -lt 2 ]]; then
  message "ERROR: Need more interface."
  exit 1
fi

# Get WAN Interface
function getwan(){
  local i ii
  echo "---------------------------------------- Process Info ----------------------------------------------"
  message "INFO: Get IPv6 global address..."
  i=0
  while true; do
    for ((ii=0;ii<${#NET[@]};ii++)); do
      ip=$(ip -j addr show ${NET[$ii]} | jq -r '.[] | .addr_info | .[] | select(.preferred_life_time != 0 and .family == "inet6" and .scope == "global") | .local')
      if [[ "$ip" != "" ]]; then
        WAN=${NET[$ii]}
        LAN=(${NET[@]:0:$ii} ${NET[@]:$ii+1})
        wan_ip=$ip
        break
      fi
    done
    if [[ "$WAN" != "" ]]; then
      break
    elif [[ $i -lt 10 ]]; then
      i=$(($i+1))
      message "WARN: No IPv6 global address, Retry $i(10)"
      sleep 1
    else
      message "ERROR: No IPv6 global address, Container stopped."
      exit 1
    fi
  done
}

function macv6map(){
  local array1 array2 a b c
  array1=(0 1 2 3 4 5 6 7 8 9 a b c d e f)
  array2=(2 3 0 1 6 7 4 5 a b 8 9 e f c d)
  a=${1:0:1}
  b=${1:1:1}
  for ((c=0;c<${#array1[@]};c++)); do
    if [[ "$b" == "${array1[$c]}" ]]; then
      mac[0]="$a${array2[$c]}"
      break
    fi
  done
}

# Get Subnet Prefix
function getprefix(){
  net_prefix=$(echo $wan_ip | cut -d : -f 1-3)
  wan_prefix=$(echo $wan_ip | cut -d : -f 4)
  if [[ ${#wan_prefix} == 1 ]]; then
    wan_prefix="0$wan_prefix"
  else
    wan_prefix=${wan_prefix:-00}
  fi
  
  if [[ "$PREFIXLEN" == "56" ]]; then
    lan_prefix="$net_prefix:${wan_prefix:0:${#wan_prefix}-2}"
    sub_prefix=(${sub00_ff[@]/${wan_prefix: -2}/})
  
  elif [[ "$PREFIXLEN" == "58" ]]; then
    lan_prefix="$net_prefix:${wan_prefix:0:${#wan_prefix}-2}"
    if [[ ${sub00_7f[@]/${wan_prefix: -2}/} != ${sub00_7f[@]} ]]; then
      sub_prefix=(${sub00_7f[@]/${wan_prefix: -2}/})
    else
      sub_prefix=(${sub80_ff[@]/${wan_prefix: -2}/})
    fi
  
  elif [[ "$PREFIXLEN" == "60" ]]; then
    lan_prefix="$net_prefix:${wan_prefix:0:${#wan_prefix}-1}"
    sub_prefix=(${sub0_f[@]/${wan_prefix: -1}/})
  
  elif [[ "$PREFIXLEN" == "62" ]]; then
    lan_prefix="$net_prefix:${wan_prefix:0:${#wan_prefix}-1}"
    if [[ ${sub0_7[@]/${wan_prefix: -1}/} != ${sub0_7[@]} ]]; then
      sub_prefix=(${sub0_7[@]/${wan_prefix: -1}/})
    else
      sub_prefix=(${sub8_f[@]/${wan_prefix: -1}/})
    fi
  
  elif [[ "$PREFIXLEN" == "64" ]]; then
    lan_prefix="$net_prefix:$wan_prefix"
    if [[ "$LAN_MODE" == "docker" ]]; then
      for ((i=0;i<${#LAN[@]};i++)); do
        v4prefixlen=$(ip -j addr show ${LAN[$i]} | jq -r '.[] | .addr_info | .[] | select (.family == "inet") | .prefixlen')
        if [[ "v4prefixlen" == "" ]]; then
          message "ERROR: No IPv4 Address, Interface must have an IPv4 address to continue."
          exit 1
        fi
        mac=($(ip -j addr show ${LAN[$i]} | jq -r '.[] | .address' | sed -e 's/:/ /g'))
        macv6map ${mac[0]}
        if [[ "$v4prefixlen" == "24" ]]; then
          sub_prefix[$i]=":${mac[0]}${mac[1]}:${mac[2]}ff:fe${mac[3]}:${mac[4]}00"
          v6prefixlen[$i]=120
        elif [[ "$v4prefixlen" == "16" ]]; then
          sub_prefix[$i]=":${mac[0]}${mac[1]}:${mac[2]}ff:fe${mac[3]}::"
          v6prefixlen[$i]=112
        elif [[ "$v4prefixlen" == "8" ]]; then
          sub_prefix[$i]=":${mac[0]}${mac[1]}:${mac[2]}ff:fe00::"
          v6prefixlen[$i]=104
        else
          message "ERROR: Unsupport IPv4 prefix length, It should be 8/16/24."
          exit 1
        fi
      done
    else
      for ((i=0;i<${#LAN[@]};i++)); do
        sub_prefix[$i]="::"
        v6prefixlen[$i]=64
      done
    fi
  else
    message "ERROR: Unsupport IPv6 prefix length, It should be 56/58/60/62/64."
    exit 1
  fi
  # Check Subnet
  if [[ "$PREFIXLEN" != "64" ]]; then
    if [[ ${#LAN[@]} -gt ${#sub_prefix[@]} ]]; then
      message "ERROR: Interfaces is so much and not enough LAN address."
      message "ERROR: [Interfaces] Num:[${#LAN[@]}] Info:[${LAN[@]}]"
      message "ERROR: [LAN address] Num:[${#sub_prefix[@]}] Info:[${sub_prefix[@]}]"
      exit 1
    fi
  elif [[ "$PREFIXLEN" == "64" && "$LAN_MODE" != "docker" ]]; then
    if [[ ${#LAN[@]} -gt 1 ]]; then
      message "ERROR: When PREFIXLEN=64 and LAN_MODE=net, Only support one lan."
      message "ERROR: [Interfaces] Num:[${#LAN[@]}] Info:[${LAN[@]}]]"
      exit 1
    fi
  fi
}

# radvd.conf
function setradvd(){
  echo "" > radvd.conf
  local i
  for ((i=0;i<${#LAN[@]};i++)); do
    # Set RA
    echo "interface ${LAN[$i]} {
      AdvSendAdvert on;
      AdvManagedFlag off;
      AdvOtherConfigFlag off;
      AdvLinkMTU $MTU;
      AdvIntervalOpt on;" >> radvd.conf
    # Set Prefix
    if [[ "$PREFIXLEN" != "64" ]]; then
      echo "prefix $1${sub_prefix[$i]}::/64 {
        AdvOnLink on;
        AdvAutonomous on;
        AdvRouterAddr off;" >> radvd.conf
    elif [[ "$PREFIXLEN" == "64" ]]; then
      echo "prefix $1::/64 {
        AdvOnLink off;
        AdvAutonomous on;
        AdvRouterAddr off;" >> radvd.conf
    fi
    # Switch Prefix
    if [[ "$2" == "switch" ]]; then
      echo "AdvValidLifetime 0;" >> radvd.conf
      echo "AdvPreferredLifetime 0;" >> radvd.conf
    fi
    echo "};" >> radvd.conf
    # Set RDNSS
    if [[ ${#RDNSS[@]} != 0 ]]; then
      echo "RDNSS ${RDNSS[@]} {
        AdvRDNSSLifetime 1800;" >> radvd.conf
      echo "};" >> radvd.conf
    fi
    echo "};" >> radvd.conf
  done
}

# ndppd.conf
function setndppd(){
  echo "" > ndppd.conf
  local i
  echo "proxy $WAN {
    router yes
    timeout 500
    ttl 30000" > ndppd.conf
  for ((i=0;i<${#LAN[@]};i++)); do
    if [[ "$PREFIXLEN" != "64" ]]; then
      echo "
        rule $lan_prefix${sub_prefix[$i]}::/64 {
          auto
        }" >> ndppd.conf
    elif [[ "$PREFIXLEN" == "64" ]]; then
      echo "
        rule $lan_prefix${sub_prefix[$i]}/${v6prefixlen[$i]} {
          auto
        }" >> ndppd.conf
    fi
  done
  echo "}" >> ndppd.conf
}

function setroute(){
  local i ii
  for ((i=0;i<${#LAN[@]};i++)); do
    ii=0
    while true; do
      lan_ip=$(ip -j addr show ${LAN[$i]} | jq -r '.[] | .addr_info | .[] | select(.preferred_life_time != 0 and .family == "inet6" and .scope == "global") | .local')
      if [[ "$lan_ip" != "" ]]; then
        ip -6 neigh add proxy $lan_ip dev $WAN
        if [[ "$PREFIXLEN" == "64" ]]; then
          ip route add $lan_prefix${sub_prefix[$i]}/${v6prefixlen[$i]} dev ${LAN[$i]}
        fi
        break
      elif [[ $ii -lt 10 ]]; then
        ii=$(($ii+1))
        message "WARN: LAN: [${LAN[$i]}] No IPv6 address, Retry $ii(10)"
        sleep 1
      else
        message "ERROR: LAN: [${LAN[$i]}] No IPv6 address, Container stopped."
        exit 1
      fi
    done
  done
}

function netinfo(){
  local i
  echo "----------------------------------------------------------------------------------------------------"
  message "INFO:  WAN: [$WAN] $wan_ip"
  for ((i=0;i<${#LAN[@]};i++)); do
    lan_ip=$(ip -j addr show ${LAN[$i]} | jq -r '.[] | .addr_info | .[] | select(.preferred_life_time != 0 and .family == "inet6" and .scope == "global") | .local')
    message "INFO:  LAN: [${LAN[$i]}] $lan_ip"
    if [[ "$PREFIXLEN" == "64" ]]; then
      message "INFO: PRFX: [${LAN[$i]}] $lan_prefix${sub_prefix[$i]}/${v6prefixlen[$i]}"
    else
      message "INFO: PRFX: [${LAN[$i]}] $lan_prefix${sub_prefix[$i]}::/64"
    fi
  done
}

function main(){
  getwan
  getprefix
  setradvd $lan_prefix
  radvd -C radvd.conf -p radvd.pid
  sleep 1
  message "INFO: radvd start with PID $(cat radvd.pid)"
  setroute
  setndppd
  ndppd -c ndppd.conf >/dev/null 2>&1 &
  echo $! > ndppd.pid
  sleep 1
  message "INFO: ndppd start with PID $(cat ndppd.pid)"
  netinfo
}

function cleanup(){
  message "INFO: Container stopped."
  kill $(cat radvd.pid)
  kill $(cat ndppd.pid)
  exit 0
}

trap 'cleanup' SIGTERM SIGINT

# Router
main
while true; do
  old_wan_ip=$wan_ip
  old_lan_prefix=$lan_prefix
  wan_ip=$(ip -j addr show $WAN | jq -r '.[] | .addr_info | .[] | select(.preferred_life_time != 0 and .family == "inet6" and .scope == "global") | .local')
  getprefix
  if [[ "$lan_prefix" != "$old_lan_prefix" ]]; then
    echo "---------------------------------------- Process Info ----------------------------------------------"
    message "INFO: WAN IPv6 address change, Process restart."
    kill $(cat radvd.pid)
    kill $(cat ndppd.pid)

    # Switch LAN Prefix
    setradvd $old_lan_prefix switch
    radvd -C radvd.conf -p radvd.pid
    sleep 3
    kill $(cat radvd.pid)

    # Clean Address
    ip addr del $old_wan_ip/64 dev $WAN
    for ((i=0;i<${#LAN[@]};i++)); do
      lan_ip=$(ip -j addr show ${LAN[$i]} | jq -r '.[] | .addr_info | .[] | select(.preferred_life_time == 0 and .family == "inet6" and .scope == "global") | .local')
      if [[ "$PREFIXLEN" == "64" ]]; then
        ip route del $old_lan_prefix${sub_prefix[$i]}/${v6prefixlen[$i]} dev ${LAN[$i]}
      fi
      ip -6 neigh del proxy $lan_ip dev $WAN
      ip addr del $lan_ip/64 dev ${LAN[$i]}
    done
    message "INFO: Old IPv6 address has been invalidated."

    # Start Service
    setradvd $lan_prefix
    radvd -C radvd.conf -p radvd.pid
    sleep 1
    message "INFO: radvd start with PID $(cat radvd.pid)"
    setroute
    setndppd
    ndppd -c ndppd.conf >/dev/null 2>&1 &
    echo $! > ndppd.pid
    sleep 1
    message "INFO: ndppd start with PID $(cat ndppd.pid)"
    netinfo
  fi
  sleep $CHECK
done

exec "$@"
