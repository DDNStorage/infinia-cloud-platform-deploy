#!/bin/bash
set -ex

_die(){
  echo "ERROR: $1" && exit 1
}


RED_SUPPORT_CONTAINER="redsupport-redsupport-1"
red_support()
{
    case $1 in
      --start)
        red-support-start="docker-compose -f /etc/red/deploy/redsupport/redsupport-compose.yml up --wait -d"
        shift
        ;;
      --lifetime)
      red-token="docker-compose -f /etc/red/deploy/redsupport/redsupport-compose.yml exec redsupport /opt/ddn/red/bin/redsupport set -e 999"
        shift
      ;;
      --token)
      lifetime-token="docker-compose -f /etc/red/deploy/redsupport/redsupport-compose.yml exec redsupport /opt/ddn/red/bin/redsupport newtoken > /tmp/red_support_token"
        shift
      ;;
  esac
}



#[ $(whoami) != "root" ] && _die "Must be root to enable remote support"
echo "start redsupport"
 red_support --start
echo "Get authentication token"
docker logs   ${RED_SUPPORT_CONTAINER} > /tmp/red_support_url 

