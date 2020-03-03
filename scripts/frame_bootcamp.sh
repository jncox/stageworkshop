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
    export PrismOpsServer='GTSPrismOpsLabUtilityServer'
    export SeedPC='GTSseedPC.zp'

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
    && create_file_server "${NW1_NAME}" "${NW2_NAME}" \
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
    && karbon_enable \
    && objects_enable \
    && lcm \
    && object_store \
    && karbon_image_download \
    && images \
    && flow_enable \
    && prism_check 'PC'

    log "Non-blocking functions (in development) follow."
    pc_project
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
