#!/usr/bin/env bash
# -x

#__main()__________

# Source Nutanix environment (PATH + aliases), then common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. global.vars.sh
begin

args_required 'EMAIL PE_PASSWORD PC_VERSION'

#dependencies 'install' 'jq' && ntnx_download 'PC' & #attempt at parallelization
# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!

case ${1} in
  PE | pe )
    . lib.pe.sh

    export AUTH_SERVER='AutoAD'

    # Networking needs for Frame Bootcamp
    export NW2_DHCP_START="${IPV4_PREFIX}.132"
    export NW2_DHCP_END="${IPV4_PREFIX}.149"
    export NW2_DHCP_START2="${IPV4_PREFIX}.250"
    export NW2_DHCP_END2="${IPV4_PREFIX}.253"

    export USERNW01_NAME='User01-Network'
    export USERNW01_VLAN=${NW2_VLAN}

    export USERNW02_NAME='User02-Network'
    export USERNW02_VLAN=${NW2_VLAN}

    export USERNW03_NAME='User03-Network'
    export USERNW03_VLAN=${NW2_VLAN}

    export USERNW04_NAME='User04-Network'
    export USERNW04_VLAN=${NW2_VLAN}

    export USERNW05_NAME='User05-Network'
    export USERNW05_VLAN=${NW2_VLAN}

    export USERNW06_NAME='User06-Network'
    export USERNW06_VLAN=${NW2_VLAN}

    export USERNW07_NAME='User07-Network'
    export USERNW07_VLAN=${NW2_VLAN}

    export USERNW08_NAME='User08-Network'
    export USERNW08_VLAN=${NW2_VLAN}

    export USERNW09_NAME='User09-Network'
    export USERNW09_VLAN=${NW2_VLAN}

    export USERNW10_NAME='User10-Network'
    export USERNW10_VLAN=${NW2_VLAN}

    export USERNW11_NAME='User11-Network'
    export USERNW11_VLAN=${NW2_VLAN}

    args_required 'PE_HOST PC_LAUNCH'
    ssh_pubkey & # non-blocking, parallel suitable

    dependencies 'install' 'sshpass' && dependencies 'install' 'jq' \
    && pe_license \
    && pe_init \
    && network_configure \
    && authentication_source \
    && pe_auth \
    && prism_pro_server_deploy \
    && files_install \
    && sleep 30 \
    && create_file_server "${NW1_NAME}" "${NW1_NAME}" \
    && sleep 30 \
    && file_analytics_install \
    && sleep 30 \
    && create_file_analytics_server \
    && sleep 30

    if (( $? == 0 )) ; then
      pc_install "${NW1_NAME}" \
      && prism_check 'PC' \

      if (( $? == 0 )) ; then
        ## TODO: If Debug is set we should run with bash -x. Maybe this???? Or are we going to use a fourth parameter
        # if [ ! -z DEBUG ]; then
        #    bash_cmd='bash'
        # else
        #    bash_cmd='bash -x'
        # fi
        # _command="EMAIL=${EMAIL} \
        #   PC_HOST=${PC_HOST} PE_HOST=${PE_HOST} PE_PASSWORD=${PE_PASSWORD} \
        #   PC_LAUNCH=${PC_LAUNCH} PC_VERSION=${PC_VERSION} nohup ${bash_cmd} ${HOME}/${PC_LAUNCH} IMAGES"
        _command="EMAIL=${EMAIL} \
           PC_HOST=${PC_HOST} PE_HOST=${PE_HOST} PE_PASSWORD=${PE_PASSWORD} \
           PC_LAUNCH=${PC_LAUNCH} PC_VERSION=${PC_VERSION} nohup bash ${HOME}/${PC_LAUNCH} IMAGES"

        cluster_check \
        && log "Remote asynchroneous PC Image import script... ${_command}" \
        && remote_exec 'ssh' 'PC' "${_command} >> ${HOME}/${PC_LAUNCH%%.sh}.log 2>&1 &" &

        pc_configure \
        && log "PC Configuration complete: Waiting for PC deployment to complete, API is up!"
        log "PE = https://${PE_HOST}:9440"
        log "PC = https://${PC_HOST}:9440"

        # parallel, optional. Versus: $0 'files' &
        #dependencies 'remove' 'sshpass'
        finish
      fi
    else
      finish
      _error=18
      log "Error ${_error}: in main functional chain, exit!"
      exit ${_error}
    fi
  ;;
  PC | pc )
    . lib.pc.sh

    #export BUCKETS_DNS_IP="${IPV4_PREFIX}.16"
    #export BUCKETS_VIP="${IPV4_PREFIX}.17"
    #export OBJECTS_NW_START="${IPV4_PREFIX}.18"
    #export OBJECTS_NW_END="${IPV4_PREFIX}.21"

    export QCOW2_IMAGES=(\
      Windows2016.qcow2 \
      Win10v1903.qcow2 \
      WinToolsVM.qcow2 \
    )
    export ISO_IMAGES=(\
      FrameCCA-2.1.0.iso \
      FrameCCA-2.1.6.iso \
      FrameGuestAgentInstaller_1.0.2.7.iso \
      Nutanix-VirtIO-1.1.5.iso \
    )

    run_once

    dependencies 'install' 'jq' || exit 13

    ssh_pubkey & # non-blocking, parallel suitable

    pc_passwd
    ntnx_cmd # check cli services available?

    export   NUCLEI_SERVER='localhost'
    export NUCLEI_USERNAME="${PRISM_ADMIN}"
    export NUCLEI_PASSWORD="${PE_PASSWORD}"
    # nuclei -debug -username admin -server localhost -password x vm.list

    if [[ -z "${PE_HOST}" ]]; then # -z ${CLUSTER_NAME} || #TOFIX
      log "CLUSTER_NAME=|${CLUSTER_NAME}|, PE_HOST=|${PE_HOST}|"
      pe_determine ${1}
      . global.vars.sh # re-populate PE_HOST dependencies
    else
      CLUSTER_NAME=$(ncli --json=true multicluster get-cluster-state | \
                      jq -r .data[0].clusterDetails.clusterName)
      if [[ ${CLUSTER_NAME} != '' ]]; then
        log "INFO: ncli multicluster get-cluster-state looks good for ${CLUSTER_NAME}."
      fi
    fi

    if [[ ! -z "${2}" ]]; then # hidden bonus
      log "Don't forget: $0 first.last@nutanixdc.local%password"
      calm_update && exit 0
    fi

    export ATTEMPTS=2
    export    SLEEP=10

    pc_init \
    && pc_dns_add \
    && pc_ui \
    && pc_auth \
    && pc_smtp

    ssp_auth \
    && calm_enable \
    && lcm \
    && pc_project \
    && images \
    && flow_enable \
    && seedPC \
    && prism_check 'PC'

    log "Non-blocking functions (in development) follow."
    #pc_project
    pc_admin
    # ntnx_download 'AOS' # function in lib.common.sh

    unset NUCLEI_SERVER NUCLEI_USERNAME NUCLEI_PASSWORD

    if (( $? == 0 )); then
      #dependencies 'remove' 'sshpass' && dependencies 'remove' 'jq' \
      #&&
      log "PC = https://${PC_HOST}:9440"
      finish
    else
      _error=19
      log "Error ${_error}: failed to reach PC!"
      exit ${_error}
    fi
  ;;
  FILES | files | afs )
    files_install
  ;;
esac
