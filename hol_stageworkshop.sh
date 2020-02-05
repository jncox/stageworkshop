#!/usr/bin/env bash
# use bash -x to debug command substitution and evaluation instead of echo.
DEBUG=

# Source Workshop common routines + global variables
source scripts/lib.common.sh
source scripts/global.vars.sh
begin

# For WORKSHOPS keyword mappings to scripts and variables, please use:
# - Calm || Bootcamp || Citrix || Summit
# - PC #.#
WORKSHOPS=(\
"Bootcamp Staging (AOS 5.11.x/AHV PC 5.11.2) = Current" \
"SNC (1-Node) Bootcamp Staging (AOS 5.11.x/AHV PC 5.11.2) = Current" \
"Frame Bootcamp Staging (AOS 5.11.x/AHV PC 5.11.2) = Current" \
"Previous Bootcamp Staging (AOS 5.11/AHV PC 5.11) = Stable" \
"Previous SNC (1-Node) Bootcamp Staging (AOS 5.11/AHV PC 5.11) = Stable" \
"In Development Bootcamp Staging (AOS 5.11+/AHV PC 5.16 RC2) = Development" \
"In Development SNC (1-Node) Bootcamp Staging (AOS 5.11+/AHV PC 5.16 RC2) = Development" \
"Tech Summit 2020 (AOS 5.11.x/AHV PC 5.11.2) = Current" \
"SNC_GTS 2020 (AOS 5.11.x/AHV PC 5.11.2) = Current" \
#"Tech Summit 2019 (AOS 5.10+/AHV PC 5.10+) = Stable" \
#"Era Bootcamp (AOS 5.11+/AHV PC 5.11+) = Development" \
#"Files Bootcamp (AOS 5.11+/AHV PC 5.11+) = Development" \
#"Citrix Bootcamp (AOS 5.11+/AHV PC 5.11+) = Development" \
#"Calm Workshop (AOS 5.8.x/AHV PC 5.8.x) = Stable" \
) # Adjust function stage_clusters, below, for file/script mappings as needed


function log() {
  local _caller

  _caller=$(echo -n "$(caller 0 | awk '{print $2}')")
  echo "$(date '+%Y-%m-%d %H:%M:%S')|$$|${_caller}|${1}"
}

function checkStagingIsDone
{
  #Set Variables
  pcIP=${1}
  clusterPW=${2}
  local _sleep=20m
  local _attempts=7
  local _loop=0
  local _test
  local _error=77


#if the snc_bootcamp.sh script is still on the CVM, then the cluster is not yet ready
  while true ; do
  (( _loop++ ))
  _test=$(sshpass -p "nutanix/4u" ssh -o StrictHostKeyChecking=no nutanix@$pcIP [[ -f /home/nutanix/.staging_complete ]] && echo "ready" || echo "notready")

    if [ "$_test" == "ready" ]; then
      log "CVM with IP of $nodeIP is ready"
        return 0
      elif (( _loop > _attempts )); then
        log "Warning ${_error} @${pcIP}: Giving up after ${_loop} tries."
        return ${_error}
      else
        log "@${1} ${_loop}/${_attempts}=${_test}: sleep ${_sleep}..."
        sleep ${_sleep}
      fi
  done
}

function stage_clusters() {
  # Adjust map below as needed with $WORKSHOPS
  local      _cluster
  local    _container
  local _dependency
  local       _fields
  local    _libraries='global.vars.sh lib.common.sh '
  local    _pe_launch # will be transferred and executed on PE
  local    _pc_launch # will be transferred and executed on PC
  local       _sshkey=${SSH_PUBKEY}
  #local       _wc_arg='--lines'
  local     _wc_arg=${WC_ARG}
  local     _workshop=${WORKSHOPS[$((${WORKSHOP_NUM}-1))]}

  # Map to latest and greatest of each point release
  # Metadata URLs MUST be specified in lib.common.sh function: ntnx_download
  # TODO: make WORKSHOPS and map a JSON configuration file?

  ## Set script vars since we know what versions we want to use
  export PC_VERSION="${PC_CURRENT_VERSION}"
  _libraries+='lib.pe.sh lib.pc.sh'
    _pe_launch='snc_bootcamp.sh'
    _pc_launch=${_pe_launch}


  dependencies 'install' 'sshpass'


  # Send configuration scripts to remote clusters and execute Prism Element script
      # shellcheck disable=2206
          PE_HOST=${1}
      PE_PASSWORD=${2}
            EMAIL=${3}
            idcluster=${4}

      mysql --login-path=local -sN<<<"Use hol; UPDATE cluster SET fk_idclusterstatus = (SELECT idclusterstatus from clusterstatus WHERE cstatus = \"Staging\") WHERE idcluster = \"${idcluster}\";" 2>&1
      echo "Node $nodeIP with cluster ID of $idcluster marked as staging"

      pe_configuration_args "${_pc_launch}"

      . /opt/scripts/stageworkshop/scripts/global.vars.sh # re-import for relative settings

      prism_check 'PE' 60

      if [[ -d cache ]]; then
        pushd cache || true
        for _dependency in ${JQ_PACKAGE} ${SSHPASS_PACKAGE}; do
          if [[ -e ${_dependency} ]]; then
            log "Sending cached ${_dependency} (optional)..."
            remote_exec 'SCP' 'PE' "${_dependency}" 'OPTIONAL'
          fi
        done
        popd || true
      fi

      if (( $? == 0 )) ; then
        log "Sending configuration script(s) to PE@${PE_HOST}"
      else
        _error=15
        log "Error ${_error}: Can't reach PE@${PE_HOST}"
        exit ${_error}
      fi

      if [[ -e ${RELEASE} ]]; then
        log "Adding release version file..."
        _libraries+=" ../${RELEASE}"
      fi

      pushd /opt/scripts/stageworkshop/scripts \
        && remote_exec 'SCP' 'PE' "${_libraries} ${_pe_launch} ${_pc_launch}" \
        && popd || exit

      # For Calm container updates...
      if [[ -d cache/pc-${PC_VERSION}/ ]]; then
        log "Uploading PC updates in background..."
        pushd cache/pc-${PC_VERSION} \
          && pkill scp || true
        for _container in epsilon nucalm ; do
          if [[ -f ${_container}.tar ]]; then
            remote_exec 'SCP' 'PE' ${_container}.tar 'OPTIONAL' &
          fi
        done
        popd || exit
      else
        log "No PC updates found in cache/pc-${PC_VERSION}/"
      fi

      if [[ -f ${_sshkey} ]]; then
        log "Sending ${_sshkey} for addition to cluster..."
        remote_exec 'SCP' 'PE' ${_sshkey} 'OPTIONAL'
      fi

      log "Remote execution configuration script ${_pe_launch} on PE@${PE_HOST}"
      remote_exec 'SSH' 'PE' "${PE_CONFIGURATION} nohup bash -x /home/nutanix/${_pe_launch} 'PE' >> ${_pe_launch%%.sh}.log 2>&1 &"
      unset PE_CONFIGURATION

      # shellcheck disable=SC2153
      cat <<EOM

  Cluster automation progress for:
  ${_workshop}
  can be monitored via Prism Element and Central.

  If your SSH key has been uploaded to Prism > Gear > Cluster Lockdown,
  the following will fail silently, use ssh nutanix@{PE|PC} instead.

  $ SSHPASS='${PE_PASSWORD}' sshpass -e ssh \\
      ${SSH_OPTS} \\
      nutanix@${PE_HOST} 'date; tail -f ${_pe_launch%%.sh}.log'
    You can login to PE to see tasks in flight and eventual PC registration:
    https://${PRISM_ADMIN}:${PE_PASSWORD}@${PE_HOST}:9440/

EOM

      if (( "$(echo ${_libraries} | grep -i lib.pc | wc ${_wc_arg})" > 0 )); then
        # shellcheck disable=2153
        cat <<EOM
  $ SSHPASS='nutanix/4u' sshpass -e ssh \\
      ${SSH_OPTS} \\
      nutanix@${PC_HOST} 'date; tail -f ${_pc_launch%%.sh}.log'
    https://${PRISM_ADMIN}@${PC_HOST}:9440/

EOM

      fi
  #Check if the cluster is ready
  checkStagingIsDone $PC_HOST $PE_PASSWORD
  rc=$?

  if [ $rc -eq 0 ] ; then
    #Update Database to mark cluster as Ready when the staging script is no longer on the CVM

    mysql --login-path=local -sN<<<"Use hol; UPDATE cluster SET fk_idclusterstatus = (SELECT idclusterstatus from clusterstatus WHERE cstatus = \"Ready\") WHERE idcluster = \"${idcluster}\";" 2>&1
    echo "Node $nodeIP with cluster ID of $idcluster marked as ready. RC is $rc"

  elif [ $rc -eq 77 ] ; then
     #Update Database to mark cluster as Error when the staging script is no longer on the CVM

      mysql --login-path=local -sN<<<"Use hol; UPDATE cluster SET fk_idclusterstatus = (SELECT idclusterstatus from clusterstatus WHERE cstatus = \"Error\") WHERE idcluster = \"${idcluster}\";" 2>&1
      echo "Node $nodeIP with cluster ID of $idcluster marked as ERROR. RC is $rc"
  
  fi

  finish
  exit
}

function pe_configuration_args() {
  local _pc_launch="${1}"

  PE_CONFIGURATION="EMAIL=${EMAIL} PRISM_ADMIN=${PRISM_ADMIN} PE_PASSWORD=${PE_PASSWORD} PE_HOST=${PE_HOST} PC_LAUNCH=${_pc_launch} PC_VERSION=${PC_VERSION}"
}


#__main__

# Source Workshop common routines + global variables
. /opt/scripts/stageworkshop/scripts/lib.common.sh
. /opt/scripts/stageworkshop/scripts/global.vars.sh
begin


# shellcheck disable=SC2213


#stage_clusters "${1}" "${2}" "${3}"

mysql --login-path=local -sN<<<"Use hol; SELECT idcluster,nodeIP,peIP,dsIP,clusterPW,clustername FROM cluster WHERE fk_idclusterstatus = (SELECT idclusterstatus from clusterstatus WHERE cstatus = \"Created\");" | while read idcluster nodeIP peIP dsIP clusterPW clustername; do
  stage_clusters "$peIP" "$clusterPW" "nutanixexpo@gmail.com" "$idcluster" &
done
