#!/usr/bin/env bash
# use bash -x to debug command substitution and evaluation instead of echo.
DEBUG=

# Source Workshop common routines + global variables
. scripts/lib.common.sh
. scripts/global.vars.sh
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
"In Development Bootcamp Staging (AOS 5.11+/AHV PC 5.11.2.1) = Development" \
"In Development SNC (1-Node) Bootcamp Staging (AOS 5.11+/AHV PC 5.11.2.1) = Development" \
"Tech Summit 2020 (AOS 5.11.x/AHV PC 5.11.2.1) = Development" \
#"SNC_GTS 2020 (AOS 5.11.x/AHV PC 5.11.2.1) = Development" \
#"Tech Summit 2019 (AOS 5.10+/AHV PC 5.10+) = Stable" \
"Citrix Bootcamp (AOS 5.11.x/AHV PC 5.11.2.1) = Development" \
"Databases with Era Bootcamp (AOS 5.11.x/AHV PC 5.11.2.1) = Development" \
"Files Bootcamp (AOS 5.11.x/AHV PC 5.11.2.1) = Development" \
"Calm Workshop (AOS 5.11.x/AHV PC 5.11.2.1) = Development" \
) # Adjust function stage_clusters, below, for file/script mappings as needed

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
  if (( $(echo ${_workshop} | grep -i "PC 5.11.2.1" | wc ${WC_ARG}) > 0 )); then
    export PC_VERSION="${PC_DEV_VERSION}"
  elif (( $(echo ${_workshop} | grep -i "PC 5.11.2" | wc ${WC_ARG}) > 0 )); then
    export PC_VERSION="${PC_CURRENT_VERSION}"
  elif (( $(echo ${_workshop} | grep -i "PC 5.11" | wc ${WC_ARG}) > 0 )); then
    export PC_VERSION="${PC_STABLE_VERSION}"
  fi

  # Map workshop to staging script(s) and libraries,
  # _pe_launch will be executed on PE
  if (( $(echo ${_workshop} | grep -i "^Bootcamp Staging" | wc ${WC_ARG}) > 0 )); then
    _libraries+='lib.pe.sh lib.pc.sh'
    _pe_launch='bootcamp.sh'
    _pc_launch=${_pe_launch}
  fi
  if (( $(echo ${_workshop} | grep -i "^SNC" | wc ${WC_ARG}) > 0 )); then
    _libraries+='lib.pe.sh lib.pc.sh'
    _pe_launch='snc_bootcamp.sh'
    _pc_launch=${_pe_launch}
  fi
  if (( $(echo ${_workshop} | grep -i "^Calm" | wc ${WC_ARG}) > 0 )); then
    _libraries+='lib.pe.sh lib.pc.sh'
    _pe_launch='calm_bootcamp.sh'
    _pc_launch=${_pe_launch}
  fi
  if (( $(echo ${_workshop} | grep -i "^Citrix" | wc ${WC_ARG}) > 0 )); then
    _libraries+='lib.pe.sh lib.pc.sh'
    _pe_launch='citrix_bootcamp.sh'
    _pc_launch=${_pe_launch}
  fi
  if (( $(echo ${_workshop} | grep -i "^Era" | wc ${WC_ARG}) > 0 )); then
    _libraries+='lib.pe.sh'
    _pe_launch='era_bootcamp.sh'
    _pc_launch=${_pe_launch}
  fi
  if (( $(echo ${_workshop} | grep -i "^Files" | wc ${WC_ARG}) > 0 )); then
    _libraries+='lib.pe.sh'
    _pe_launch='files_bootcamp.sh'
    _pc_launch=${_pe_launch}
  fi
  if (( $(echo ${_workshop} | grep -i Summit | wc ${WC_ARG}) > 0 )); then
    _libraries+='lib.pe.sh lib.pc.sh'
    _pe_launch='ts2020.sh'
    _pc_launch=${_pe_launch}
  fi
  if (( $(echo ${_workshop} | grep -i "^SNC_GTS" | wc ${WC_ARG}) > 0 )); then
    _libraries+='lib.pe.sh lib.pc.sh'
    _pe_launch='snc_ts2020.sh'
    _pc_launch=${_pe_launch}
  fi
  if (( $(echo ${_workshop} | grep -i "^Frame" | wc ${WC_ARG}) > 0 )); then
    _libraries+='lib.pe.sh lib.pc.sh'
    _pe_launch='frame_bootcamp.sh'
    _pc_launch=${_pe_launch}
  fi

  dependencies 'install' 'sshpass'

  if [[ -z ${PC_VERSION} ]]; then
    log "WORKSHOP #${WORKSHOP_NUM} = ${_workshop} with PC-${PC_VERSION}"
  fi

  # Send configuration scripts to remote clusters and execute Prism Element script
  if [[ ${CLUSTER_LIST} == '-' ]]; then
    echo "Login to see tasks in flight via https://${PRISM_ADMIN}:${PE_PASSWORD}@${PE_HOST}:9440"
    pe_configuration_args "${_pc_launch}"

    pushd scripts || true
    eval "${PE_CONFIGURATION} ./${_pe_launch} 'PE'" >> ${HOME}/${_pe_launch%%.sh}.log 2>&1 &
    unset PE_CONFIGURATION
    popd || true
  else
    for _cluster in $(cat ${CLUSTER_LIST} | grep -v ^#)
    do
      set -f
      # shellcheck disable=2206
          _fields=(${_cluster//|/ })
          PE_HOST=${_fields[0]}
      PE_PASSWORD=${_fields[1]}
            EMAIL=${_fields[2]}

      pe_configuration_args "${_pc_launch}"

      . scripts/global.vars.sh # re-import for relative settings

      cat <<EoM
______Warning -- curl time out indicates either:
      - Network routing issue (perhaps you're not on VPN?),
      - Foundation and initialization (Cluster IP API response) hasn't completed.
EoM

      _error=$(prism_check 'PE' '1')
      # If we were unable to connect to the PRISM UI, send a message to the console and move to the next
      if [[ ${_error} != *"successful"* ]]; then
        log "We were unable to connect to the PRISM UI on ${PE_HOST}..."
        continue
      fi


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

      pushd scripts \
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
      ## TODO: If DEBUG is set, we run the below command with bash -x
      remote_exec 'SSH' 'PE' "${PE_CONFIGURATION} nohup bash /home/nutanix/${_pe_launch} 'PE' >> ${_pe_launch%%.sh}.log 2>&1 &"
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
    done

  fi
  finish
  exit
}

function pe_configuration_args() {
  local _pc_launch="${1}"

  PE_CONFIGURATION="EMAIL=${EMAIL} PRISM_ADMIN=${PRISM_ADMIN} PE_PASSWORD=${PE_PASSWORD} PE_HOST=${PE_HOST} PC_LAUNCH=${_pc_launch} PC_VERSION=${PC_VERSION}"
}

function validate_clusters() {
  local _cluster
  local  _fields

  for _cluster in $(cat ${CLUSTER_LIST} | grep -v ^\#)
  do
    set -f
    # shellcheck disable=2206
        _fields=(${_cluster//|/ })
        PE_HOST=${_fields[0]}
    PE_PASSWORD=${_fields[1]}

    prism_check 'PE'
    if (( $? == 0 )) ; then
      log "Success: execute PE API on ${PE_HOST}"
    else
      log "Failure: cannot validate PE API on ${PE_HOST}"
    fi
  done
}

function script_usage() {
  local _offbyone

  cat << EOF

See README.md and documentation/guidebook.md for more information.

    Interactive Usage: $0
Non-interactive Usage: $0 -f [${_CLUSTER_FILE}] -w [workshop_number]
Non-interactive Usage: EMAIL=first.last@nutanix.com PE_HOST=10.x.x.37 PRISM_ADMIN=admin PE_PASSWORD=examplePW $0 -f -

Available Workshops:
EOF

  for (( i = 0; i < ${#WORKSHOPS[@]}-${NONWORKSHOPS}; i++ )); do
    let _offbyone=$i+1
    echo "${_offbyone} = ${WORKSHOPS[$i]}"
  done

  exit
}

function get_file() {
  local _error=55

  if [[ "${CLUSTER_LIST}" != '-' ]]; then
    echo
    read -p "$_CLUSTER_FILE: " CLUSTER_LIST # Prompt user

    if [[ ! -f "${CLUSTER_LIST}" ]]; then
      echo "Warning ${_error}: file not found = ${CLUSTER_LIST}. Use: Control+C to cancel."
      get_file
    fi
  fi

  echo
  select_workshop
}

function select_workshop() {
  # Get workshop selection from user, set script files to send to remote clusters
  PS3='Select an option: '
  select WORKSHOP in "${WORKSHOPS[@]}"
  do
    case $WORKSHOP in
      "Change ${_CLUSTER_FILE}")
        CLUSTER_LIST= # reset
        get_file
        break
        ;;
      "Validate Staged Clusters")
        validate_clusters
        break
        ;;
      "Quit")
        exit
        ;;
      *)
        for (( i = 0; i < ${#WORKSHOPS[@]}-${NONWORKSHOPS}; i++ )); do
          if [[ ${WORKSHOPS[$i]} == "${WORKSHOP}" ]]; then
            let WORKSHOP_NUM=$i+1
          fi
        done

        if [[ ${WORKSHOP_NUM} == "" ]]; then
          echo -e "\nInvalid entry = ${WORKSHOP}, please try again."
        else
          #log "Matched: workshop ${WORKSHOP}!"
          break
        fi
        ;;
    esac
  done

  echo -e "\nAre you sure you want to stage ${WORKSHOP} to the cluster(s) provided? \
    \nYour only 'undo' option is running Foundation on your cluster(s) again."
  read -p '(Y/N)' -n 1 -r

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo
    stage_clusters
  else
    echo -e "\nCome back soon!"
  fi
}

#__main__

    _VALIDATE='Validate Staged Clusters'
_CLUSTER_FILE='Cluster Input File'
 CLUSTER_LIST=

# NONWORKSHOPS appended to WORKSHOPS
             WORKSHOP_COUNT=${#WORKSHOPS[@]}
WORKSHOPS[${#WORKSHOPS[@]}]="Change ${_CLUSTER_FILE}"
WORKSHOPS[${#WORKSHOPS[@]}]=${_VALIDATE}
WORKSHOPS[${#WORKSHOPS[@]}]="Quit"
           let NONWORKSHOPS=${#WORKSHOPS[@]}-${WORKSHOP_COUNT}

# shellcheck disable=SC2213
while getopts "f:w:\?" opt; do

  if [[ ${DEBUG} ]]; then
    log "Checking option: ${opt} with argument ${OPTARG}"
  fi

  case ${opt} in
    f )
      if [[ ${OPTARG} == '-' ]]; then
        log "${_CLUSTER_FILE} override, checking environment variables..."

        if [[ -z "${PE_HOST}" ]]; then
          pe_determine 'PE'
          . global.vars.sh # re-populate PE_HOST dependencies
        fi

        args_required 'EMAIL PE_HOST PE_PASSWORD'
        CLUSTER_LIST=${OPTARG}
      elif [[ -f ${OPTARG} ]]; then
        CLUSTER_LIST=${OPTARG}
      else
        echo "Error: file not $(($OPTARG)) < $((${#WORKSHOPS[@]}-${NONWORKSHOPS}+1)) found = ${OPTARG}"
        script_usage
      fi
      ;;
    w )
      if (( $(($OPTARG)) > 0 )) \
      && (( $(($OPTARG)) < $((${#WORKSHOPS[@]}-${NONWORKSHOPS}+1)) )); then
        WORKSHOP_NUM=${OPTARG}
      else
        echo "Error: workshop not found = ${OPTARG}"
        script_usage
      fi
      ;;
    \? )
      script_usage
      ;;
  esac
done
shift $((OPTIND -1))

if [[ -z ${CLUSTER_LIST} ]]; then
  get_file
fi
if [[ -z ${WORKSHOP_NUM} ]]; then
  log "Warning: missing workshop number argument."
  select_workshop
fi

if [[ ${WORKSHOPS[${WORKSHOP_NUM}]} == "${_VALIDATE}" ]]; then
  validate_clusters
elif (( ${WORKSHOP_NUM} == ${#WORKSHOPS[@]} - 1 )); then
  echo ${WORKSHOPS[${WORKSHOP_NUM}]}
  finish
elif (( ${WORKSHOP_NUM} == ${#WORKSHOPS[@]} - 2 )); then
  echo ${WORKSHOPS[${WORKSHOP_NUM}]}
elif (( ${WORKSHOP_NUM} > 0 && ${WORKSHOP_NUM} <= ${#WORKSHOPS[@]} - 3 )); then
  stage_clusters
else
  #log "DEBUG: WORKSHOP_NUM=${WORKSHOP_NUM}"
  script_usage
fi
