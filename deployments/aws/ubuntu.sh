#!/bin/bash
# @copyright
#                               --- WARNING ---
#
#     This work contains trade secrets of DataDirect Networks, Inc.  Any
#     unauthorized use or disclosure of the work, or any part thereof, is
#     strictly prohibited. Any use of this work without an express license
#     or permission is in violation of applicable laws.
#
# @copyright DataDirect Networks, Inc. CONFIDENTIAL AND PROPRIETARY
# @copyright DataDirect Networks Copyright, Inc. (c) 2021-2024. All rights reserved.

function mark_limits_conf {
	# make change in limits.conf to force reboot on successful bootstrapping.
	# this is work around for failed bootstrap that has updated system params but
	# then fails. This function ensures reboot when retry of redsetup eventually
	# succeeds
	echo ">>> undo limits.conf changes"
        sed -e '/^root/ s/^root/# root/' -i /etc/security/limits.conf
}

function check_servers {
  n=1
  t=0
  while [ $n -gt 0 ]
  do
    if [ $t -gt 3600 ]; then
       echo "Wait timeout exeeded 60 minutes, exiting."
       touch redfailed
       exit 1
    fi
    n=0
    for srv in $servers
    do
       echo "Checking https://${srv}:443/redsetup/v1/system/status"
       wget --no-check-certificate \
        --certificate=/etc/red/certs/redsetup_client_cert.pem \
        --private-key=/etc/red/certs/redsetup_client_key.pem \
         "https://${srv}:443/redsetup/v1/system/status"
       if [ "$?" -ne "0" ]
       then
           n=$((n+1))
       fi
    done
    if [ $n -gt 0 ]; then
       echo "Got $n error responses, sleeping for 20 sec"
       t=$((t+20))
       sleep 20
    fi
  done
}

function check_images {
  # Workaround until redsetup / red realm operations support pulling container images by registry & label
  # If using custom container images, pull those and tag them here before running redsetup realm-entry steps
  if [ "${REGISTRY}" == "quay.io" ] ; then
    echo ">>> Using default container registry ${REGISTRY} and red version ${RED_VER} no action required."
    return
  fi
}

function check_registration_count {
  redapi_login
  t=0
  sa=($servers)
  server_count=${#sa[@]}
  while [ $n -lt $server_count ]
  do
    if [ $t -gt 3600 ]; then
       echo "Wait timeout exeeded 60 minutes, exiting."
       touch redfailed
       exit 1
    fi
    n=`redcli inventory show -o json | jq '.data.nodes | length'`
    echo "Checking server count in inventory - $n of $server_count found"
    if [ $n -lt $server_count ]; then
      echo "Sleeping for 10 sec"
       t=$((t+10))
       sleep 10
    fi
  done
}

function redapi_login {
  if [[ ! -z "$1" ]] ;  then
    CLI_SERVER_STRING="REDCLI_SERVER=https://$1:443/redapi/v1"
  fi
  t=0
  while [ $t -lt 1200 ]
  do
    bash -c "$CLI_SERVER_STRING redcli user login realm_admin -p $ADMIN_PWD"
    if [ $? -gt 0 ]; then
       echo "Got redapi login error, sleeping for 10 sec"
       t=$((t+10))
       sleep 10
    else
       return
    fi
  done
  if [ $t -ge 1200 ]; then
      echo "Redapi login wait timeout exeeded 5 minutes, exiting."
      touch redfailed
      exit 1
  fi
}

function write_ca_cert {
  if [ "x$CA" == "x" ] || [ "x$CA_KEY" == "x" ]; then
    echo "CA certificate not provided, creating a new one."
    return
  fi
  echo "Writing CA certificate."
  home=`pwd`
  mkdir -p $home/red/certs
  echo -n $CA > $home/red/certs/ca.pem
  sed -i -e 's/|/\n/g' $home/red/certs/ca.pem
  echo -n  $CA_KEY > $home/red/certs/ca_key.pem
  sed -i -e 's/|/\n/g' $home/red/certs/ca_key.pem
}

function get_client_certs {
  # copy certs from deployment node
  mkdir -p /etc/red/certs
  cd /etc/red/certs
  scp $DEPLOY_DRIVER:/etc/red/certs/ca.pem .
  scp $DEPLOY_DRIVER:/etc/red/certs/etcd_admin_001.pem .
  scp $DEPLOY_DRIVER:/etc/red/certs/etcd_admin_001-key.pem .
  chmod 644 /etc/red/certs/*.pem
}

function wait_for_user_create {
  # wait for gcp to create user home directory
  t=0
  while [ $t -lt 60 ]
  do
    # user home may not be defined if user is not created so reassign here
    USER_HOME=$( getent passwd "${USER_NAME}" | cut -d: -f6 )
    bash -c "ls -l ${USER_HOME}/.ssh"
    if [ $? -gt 0 ]; then
       echo "Waiting for ${USER_HOME} to be created, sleeping for 10 sec"
       t=$((t+10))
       sleep 10
    else
       return
    fi
  done
  if [ $t -ge 60 ]; then
      echo "User create for ${USER_NAME} exceeded 1 minute, exiting."
      touch redfailed
      exit 1
  fi
}

function setup_ssh_access {
  wait_for_user_create
  # write certs for current user
  echo ">>> Setup passwordless ssh access for RED nodes"
  echo $SSH_ACCESS_KEY > ${USER_HOME}/.ssh/id_rsa.pub
  echo $SSH_ACCESS_KEY >> ${USER_HOME}/.ssh/authorized_keys
  echo $SSH_ACCESS_PKEY > ${USER_HOME}/.ssh/id_rsa
  sed -i -e 's/|/\n/g' ${USER_HOME}/.ssh/id_rsa
  chmod 600 ${USER_HOME}/.ssh/id_rsa
  echo "StrictHostKeyChecking no" >> ${USER_HOME}/.ssh/config
  chown ${USER_NAME}:${USER_NAME} ${USER_HOME}/.ssh/id_rsa
  chown ${USER_NAME}:${USER_NAME} ${USER_HOME}/.ssh/id_rsa.pub
  chown ${USER_NAME}:${USER_NAME} ${USER_HOME}/.ssh/config
}

function get_server_ips {
    server_ips=""
    for i in $servers
    do
       h=`host $i`
       h=${h##* }
       if [ "x$server_ips" == "x" ]; then
         server_ips="$h"
       else
         server_ips="${server_ips},$h"
       fi
    done
    return
}

function client_node {
    if echo "$CLIENT_ADDRS" | grep -q -w "$HOSTNAME" ; then
        return 0
    fi
    return 1
}

function agent_node {
    if echo "$AGENT_ADDRS" | grep -q -w "$HOSTNAME" ; then
        return 0
    fi
    return 1
}

function deploy_driver {
    if [ $HOSTNAME == $DEPLOY_DRIVER ]; then
        return 0
    fi
    return 1
}

function generate_node_description_file {
    echo "nodes_per_rack is $nodes_per_rack"
    echo "racks_per_hall is $racks_per_hall"
    nodes_per_hall=$((nodes_per_rack * racks_per_hall))
    node_idx=${HOSTNAME##${HOST_PREFIX}}
    echo "The node_idx is ${node_idx}"
    # calculate the ceil of node_idx/nodes_per_hall
    hall_num=$(( (node_idx + nodes_per_hall-1) / nodes_per_hall ))
    node_idx_inhall=$((node_idx % nodes_per_hall))
    if (( node_idx_inhall == 0))
    then
      # if the reminder is 0, let it be the maximum nodes per hall
      ((node_idx_inhall=nodes_per_hall))
    fi
    # calculate the ceil of node_idx_inhall/nodes_per_rack
    rack_num=$(( (node_idx_inhall + nodes_per_rack -1) / nodes_per_rack))
    slot_num=$(( node_idx_inhall  % nodes_per_rack ))
    if (( slot_num == 0))
    then
       ((slot_num=nodes_per_rack))
    fi
    if ((slot_num <= $((nodes_per_rack /2)) ))
    then
      #fill the bottom first
      subrack="bottom"
    else
      subrack="top"
    fi
    cat<<EOF >${USER_HOME}/node_description_file.json
{
    "hostname": "$HOSTNAME",
    "location": {
        "site": "site1",
        "hall": "hall${hall_num}",
        "rack": "rack${rack_num}",
        "subrack": "${subrack}",
        "slot": "${slot_num}",
        "size": "1U"
    }
}
EOF
echo "The file ${USER_HOME}/node_description_file.json is generated"
}

USER_NAME=$(curl http://metadata/computeMetadata/v1/instance/attributes/username -H "Metadata-Flavor: Google")
ALL_ADDRS=$(curl http://metadata/computeMetadata/v1/instance/attributes/all_servers -H "Metadata-Flavor: Google")
CLIENT_ADDRS=$(curl http://metadata/computeMetadata/v1/instance/attributes/client_servers -H "Metadata-Flavor: Google")
AGENT_ADDRS=$(curl http://metadata/computeMetadata/v1/instance/attributes/agent_servers -H "Metadata-Flavor: Google")
DEPLOY_DRIVER=$(curl http://metadata/computeMetadata/v1/instance/attributes/deploy_driver -H "Metadata-Flavor: Google")
CLUSTER=$(curl http://metadata/computeMetadata/v1/instance/attributes/clustername -H "Metadata-Flavor: Google")
NO_SECURITY=$(curl http://metadata/computeMetadata/v1/instance/attributes/no_security  -H "Metadata-Flavor: Google")
CA=$(curl http://metadata/computeMetadata/v1/instance/attributes/ca -H "Metadata-Flavor: Google")
CA_KEY=$(curl http://metadata/computeMetadata/v1/instance/attributes/ca_key -H "Metadata-Flavor: Google")
INSTALL_ONLY=$(curl http://metadata/computeMetadata/v1/instance/attributes/install_only -H "Metadata-Flavor: Google")
PROVISION_ONLY=$(curl http://metadata/computeMetadata/v1/instance/attributes/provision_only -H "Metadata-Flavor: Google")
SSH_ACCESS_KEY=$(curl http://metadata/computeMetadata/v1/instance/attributes/ssh_access_key -H "Metadata-Flavor: Google")
SSH_ACCESS_PKEY=$(curl http://metadata/computeMetadata/v1/instance/attributes/ssh_access_pkey -H "Metadata-Flavor: Google")
REGISTRY=$(curl http://metadata/computeMetadata/v1/instance/attributes/registry -H "Metadata-Flavor: Google")
RED_VER=$(curl http://metadata/computeMetadata/v1/instance/attributes/container_label -H "Metadata-Flavor: Google")
PROD_BUILD=$(curl http://metadata/computeMetadata/v1/instance/attributes/production_build -H "Metadata-Flavor: Google")
PKG_PATH=$(curl http://metadata/computeMetadata/v1/instance/attributes/package_path -H "Metadata-Flavor: Google")
ADMIN_PWD=$(curl http://metadata/computeMetadata/v1/instance/attributes/realm_admin_password -H "Metadata-Flavor: Google")
HOST_PREFIX=$(curl http://metadata/computeMetadata/v1/instance/attributes/host_prefix -H "Metadata-Flavor: Google")
ADD_NODE_DESC=$(curl http://metadata/computeMetadata/v1/instance/attributes/add_node_desc -H "Metadata-Flavor: Google")
nodes_per_rack=$(curl http://metadata/computeMetadata/v1/instance/attributes/nodes_per_rack -H "Metadata-Flavor: Google")
racks_per_hall=$(curl http://metadata/computeMetadata/v1/instance/attributes/racks_per_hall -H "Metadata-Flavor: Google")
MODS=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/mods" -H "Metadata-Flavor: Google" )
HW_OVERRIDE=$(curl --fail "http://metadata.google.internal/computeMetadata/v1/instance/attributes/hw_override" -H "Metadata-Flavor: Google" )
servers=${AGENT_ADDRS//,/ }
USER_HOME=$( getent passwd "${USER_NAME}" | cut -d: -f6 )
HOSTNAME=`hostname -s`

cd ~

if [ -e "redinst" ]; then
    echo ">>> Step 2. After reboot"
    echo "Add $USER_NAME to docker group"
    /usr/sbin/usermod -aG docker $USER_NAME
    if [[ "$INSTALL_ONLY" == "true" || "$PROVISION_ONLY" == "true" ]]; then
        echo ">>> Install only requested - finished"
        touch redready
    elif deploy_driver ; then
        echo "ALL_ADDRS=$ALL_ADDRS"
        echo "AGENT_ADDRS=$AGENT_ADDRS"
        echo "CLUSTER=$CLUSTER"
        echo "NO_SECURITY=$NO_SECURITY"
        export REDCLI_SERVER=https://127.0.0.1:443/redapi/v1
        check_servers
        check_registration_count
        write_ca_cert

        # disable stats with "-D" flag
        # do not pass list of agents, use default
        cmd="redcli realm config generate -D"
        if [ "$NO_SECURITY" == "true" ]; then
            cmd="${cmd} -n"
        fi
        echo "Sleep 10s before generate"
        sleep 10
        redapi_login
        echo "$cmd"
        eval "$cmd"
        realm_config_file="realm_config.yaml"
        if [ -e ${realm_config_file} ]; then
            updatecmd="redcli realm config update"
            echo "$updatecmd"
            eval "$updatecmd"
            if [ $? -gt 0 ]; then
                echo "Realm create failed"
                touch redfailed
                exit 1
            fi
            echo "Sleep 10s after update"
            sleep 10
            if [ "x$AGENT_ADDRS" != "x" ]; then
                if [ "$PROD_BUILD" == "true" ]; then
                    echo ">>> Install license key for production build"
                    redcli license install -a E0C90338-A053-4A91-ADA3-3C11C21DEFF4 -y
                fi
                echo "Create cluster"
                cluster_cmd="redcli cluster create $CLUSTER -S=false -z --debug tunables.liveness_timeout=32 -f"
                if [ "$ADD_NODE_DESC" == "true" ]
                then
                    cluster_cmd="${cluster_cmd} -A hall"
                fi
                redapi_login
                echo "$cluster_cmd"
                eval "$cluster_cmd"
            fi
            touch redready
        else
            echo "Error - realm_config file not found. Exiting."
            touch redfailed
            exit 1
        fi
    fi
else
    echo ">>> Step 1. Setup nodes"
    touch redinst
    echo ">>> Run apt update for all nodes"
    apt update -y

    echo ">>> Run system mods"
    echo "Mods: ${MODS}"
    for mod in $MODS; do
        # store mod url in var
        mod_url="http://metadata.google.internal/computeMetadata/v1/instance/attributes/mod-file-${mod}"
        echo "Downloading mod: ${mod_url}"
        if ! curl -o /tmp/modfile.sh "${mod_url}" -H "Metadata-Flavor: Google" 2>/tmp/curl_error; then
            echo "Error downloading mod ${mod_url}:"
            cat /tmp/curl_error
            continue
        fi

        echo "Executing mod: ${mod}"
        if ! . /tmp/modfile.sh 2>/tmp/mod_error; then
            echo "Error executing mod ${mod}:"
            cat /tmp/mod_error
        fi
    done

    # setup passwordless access between instances - this is done to facilitate configuring
    # redclient instances; and will not be required when all clients used restapi for getting
    # daemon info block.
    setup_ssh_access

    if [ "$PROD_BUILD" == "true" ]; then
        echo ">>> Using production build packages and container images"
    else
        echo ">>> Using engineering build packages and container images"
    fi


    # need to export RED_VER so its picked up by envsub command
    export RED_VER=$RED_VER
    echo ">>> RED_VER: $RED_VER"

    BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
    if client_node ; then
        # include redtools package in install
        CLNT_COMMON_PATH=$(echo $PKG_PATH | sed 's/redcli/red-client-common/')
        CLNT_TOOLS_PATH=$(echo $PKG_PATH | sed 's/redcli/red-client-tools/')
        CLNT_FS_PATH=$(echo $PKG_PATH | sed 's/redcli/red-client-fs/')
        echo ">>> Client node - install required packages"
        curl http://archive.ubuntu.com/ubuntu/pool/main/libu/liburing/liburing1_0.6-3ubuntu1_amd64.deb -o liburing1-0.6.deb
        sudo apt install -y ./liburing1-0.6.deb
        # add cache-time param to force cache refresh
        echo ">>> Client node - install $PKG_PATH"
        wget $PKG_PATH?cache-time="$(date +%s)" -O /tmp/redcli.deb && sudo apt install -y /tmp/redcli.deb
        echo ">>> Client node - install $CLNT_COMMON_PATH"
        wget $CLNT_COMMON_PATH?cache-time="$(date +%s)" -O /tmp/red-client-common.deb && sudo apt install -y /tmp/red-client-common.deb
        echo ">>> Client node - install $CLNT_TOOLS_PATH"
        wget $CLNT_TOOLS_PATH?cache-time="$(date +%s)" -O /tmp/red-client-tools.deb && sudo apt install -y /tmp/red-client-tools.deb
        echo ">>> Client node - install $CLNT_FS_PATH"
        wget $CLNT_FS_PATH?cache-time="$(date +%s)" -O /tmp/red-client-fs.deb && sudo apt install -y /tmp/red-client-fs.deb
        # allow client root account to scp certificates from $DEPLOY_DRIVER
        cp ${USER_HOME}/.ssh/id_rsa /root/.ssh/
        cp ${USER_HOME}/.ssh/id_rsa.pub /root/.ssh/
        cp ${USER_HOME}/.ssh/config /root/.ssh/
        # wait for api server on $DEPLOY_DRIVER to be up
        redapi_login $DEPLOY_DRIVER
        # copy certs from $DEPLOY_DRIVER and set environment
        get_client_certs
        # create /var/log/red directory
        mkdir -p /var/log/red
        chmod 777 /var/log/red

    elif agent_node ; then
        echo ">>> Agent node - install $PKG_PATH"
        echo "export REDCLI_SERVER=https://127.0.0.1:443/redapi/v1" >> .bashrc
        # add cache-time param to force cache refresh
        get_redsetup="wget $PKG_PATH?cache-time=\"\$(date +%s)\" -O /tmp/redsetup.deb && sudo apt install -y /tmp/redsetup.deb"
        set_redalias="cat /opt/ddn/red/red_aliases >> ${USER_HOME}/.bash_aliases"
        realm_entry_cmd="sudo redsetup --realm-entry-secret realm_secret --admin-password $ADMIN_PWD \
                          --realm-entry --ctrl-plane-ip $(hostname --ip-address) --skip-hardware-check"
        copy_ssh_keys="cat ${USER_HOME}/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys"
        realm_register_cmd="/usr/bin/redsetup --realm-entry-secret realm_secret \
                             --realm-entry-address $DEPLOY_DRIVER --skip-hardware-check"
	# TODO: remove "mkdir /etc/docker" after PR lands
	redsetup_workaround_cmd="/usr/bin/mkdir -p /etc/docker"
	redsetup_reset_cmd="/usr/bin/redsetup --reset"

        if [ "$ADD_NODE_DESC" == "true" ]; then
            generate_node_description_file
            realm_entry_cmd="${realm_entry_cmd} --node-description-file ${USER_HOME}/node_description_file.json"
            realm_register_cmd="${realm_register_cmd} --node-description-file ${USER_HOME}/node_description_file.json"
        fi
        if [ "$PROVISION_ONLY" == "true" ]; then
            echo "Set to provision only. Run the following commands to install RED software:"
            echo "  export RED_VER=$RED_VER"
            echo "  $get_redsetup"
            echo "  $set_redalias"
            if deploy_driver ; then
                echo "  $copy_ssh_keys"
                echo "  $realm_entry_cmd"
            else
                echo "  $realm_register_cmd"
            fi
            exit 0
        fi

        eval "$get_redsetup"

        if [[ -n "$HW_OVERRIDE" ]]; then
            HWCONFIG_FILE=/opt/ddn/red/hwconfig-files/Google_Compute_Engine-overrides.yaml
            mv ${HWCONFIG_FILE} ${HWCONFIG_FILE}.orig
            echo ">>> Using custom hardware override for ${HWCONFIG_FILE}"
            echo "$HW_OVERRIDE" > ${HWCONFIG_FILE}
        fi

        eval "$set_redalias"
        # allow client nodes to scp from deploy driver
        if deploy_driver ; then
            eval "$copy_ssh_keys"
            echo ">>> Deployment driver - run redsetup as realm-entry node"
            echo "$realm_entry_cmd"
            eval "$realm_entry_cmd"
        else
            echo ">>> Not deployment driver - register with $DEPLOY_DRIVER"
	    echo ">>> Wait for deployment driver to bootstrap"
	    # retry up to 20 times with 30 second wait when registration fails
	    for i in {1..20} ; do
		http_code=$(curl -s -k -w "%{http_code}" -o /dev/null https://$DEPLOY_DRIVER/redapi/v1/info)
		echo ">>> redapi query status $http_code - attempt $i"
		if [ $http_code -eq 200 ] ; then
		    echo ">>> redapi server is available"
		    echo "${realm_register_cmd} - attempt $i"
		    eval "${realm_register_cmd}" && break || eval "${redsetup_workaround_cmd}" && eval "${redsetup_reset_cmd}" && sleep 30
		else
		    echo ">>> redapi is not ready - wait 30s and retry"
		    sleep 30
		fi
	    done
        fi
    fi
fi
