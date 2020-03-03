#!/usr/bin/env bash
# dependencies: dig

##################################################################################
# List of date, who  and change made to the file
# --------------------------------------------------------------------------------
# 12-04-2019 - Willem Essenstam
# Changed the run_once function so it checks not on lines in the log file but
# on if the PC is configured by trying to log in using the set password
##################################################################################

##################################################################################

function args_required() {
  local _argument
  local    _error=88

  for _argument in ${1}; do
    if [[ ${DEBUG} ]]; then
      log "DEBUG: Checking ${_argument}..."
    fi
    _RESULT=$(eval "echo \$${_argument}")
    if [[ -z ${_RESULT} ]]; then
      log "Error ${_error}: ${_argument} not provided!"
      exit ${_error}
    elif [[ ${DEBUG} ]]; then
      log "Non-error: ${_argument} for ${_RESULT}"
    fi
  done

  if [[ ${DEBUG} ]]; then
    log 'Success: required arguments provided.'
  fi
}

##################################################################################

function begin() {
  local _release

  if [[ -e ${RELEASE} ]]; then
    _release=" release: $(grep FullSemVer ${RELEASE} | awk -F\" '{print $4}')"
  fi

  log "$(basename ${0})${_release} start._____________________"
}

##################################################################################

function dependencies {
  local    _argument
  local       _error
  local       _index
  local      _jq_pkg=${JQ_REPOS[0]##*/}
  local _sshpass_pkg=${SSHPASS_REPOS[0]##*/}

  if [[ -z ${1} ]]; then
    _error=20
    log "Error ${_error}: missing install or remove verb."
    exit ${_error}
  elif [[ -z ${2} ]]; then
    _error=21
    log "Error ${_error}: missing package name."
    exit ${_error}
  elif [[ "${1}" != 'install' ]] && [[ "${1}" != 'remove' ]]; then
    _error=20
    log "Error ${_error}: wrong install or remove verb (case sensitive)."
    exit ${_error}
  fi

  case "${1}" in
    'install')

      if [[ -z $(which ${2}) ]]; then
        log "Install ${2}..."
        case "${2}" in
          sshpass | ${_sshpass_pkg})
            if [[ ( ${OS_NAME} == 'Ubuntu' || ${OS_NAME} == 'LinuxMint' ) ]]; then
              sudo apt-get install --yes sshpass
            elif [[ ${OS_NAME} == '"centos"' ]]; then
              # TOFIX: assumption, probably on NTNX CVM or PCVM = CentOS7
              if [[ ! -e ${_sshpass_pkg} ]]; then
                repo_source SSHPASS_REPOS[@] ${_sshpass_pkg}
                download ${SOURCE_URL}
              fi
              sudo rpm -ivh ${_sshpass_pkg}
              if (( $? > 0 )); then
                _error=31
                log "Error ${_error}: cannot install ${2}."
                exit ${_error}
              fi
            elif [[ ${OS_NAME} == 'Darwin' ]]; then
              brew install https://raw.githubusercontent.com/kadwanev/bigboybrew/master/Library/Formula/sshpass.rb
            fi
            ;;
          jq | ${_jq_pkg} )
            if [[ ( ${OS_NAME} == 'Ubuntu' || ${OS_NAME} == 'LinuxMint' ) ]]; then
              if [[ ! -e ${_jq_pkg} ]]; then
                sudo apt-get install --yes jq
              fi
            elif [[ ${OS_NAME} == '"centos"' ]]; then
              if [[ ! -e ${_jq_pkg} ]]; then
                 repo_source JQ_REPOS[@] ${_jq_pkg}
                 download ${SOURCE_URL}
              fi
              chmod u+x ${_jq_pkg} && ln -s ${_jq_pkg} jq

              if [[ -d ${HOME}/bin ]]; then
                mv jq* ${HOME}/bin/
              else
                PATH+=:$(pwd)
                export PATH
              fi
            elif [[ ${OS_NAME} == 'Darwin' ]]; then
              brew install jq
            fi
            ;;
        esac

        if (( $? > 0 )); then
          _error=98
          log "Error ${_error}: can't install ${2}."
          exit ${_error}
        fi
      else
        log "Success: found ${2}."
      fi
      ;;
    'remove')
      if [[ ${OS_NAME} == '"centos"' ]]; then
        log "Warning: assuming on PC or PE VM, removing ${2}..."
        case "${2}" in
          sshpass | ${_sshpass_pkg})
            sudo rpm -e sshpass
          ;;
          jq | ${_jq_pkg} )
            if [[ -d ${HOME}/bin ]]; then
              pushd bin || true
              rm -f jq ${_jq_pkg}
              popd || true
            else
              rm -f jq ${_jq_pkg}
            fi
          ;;
        esac
      else
        log "Feature: don't remove dependencies on Mac OS Darwin, Ubuntu, or LinuxMint."
      fi
      ;;
  esac
}

##################################################################################

function dns_check() {
  local    _dns
  local  _error
  local _lookup=${1} # REQUIRED
  local   _test

  if [[ -z ${_lookup} ]]; then
    _error=43
    log "Error ${_error}: missing lookup record!"
    exit ${_error}
  fi

   _dns=$(dig +retry=0 +time=2 +short @${AUTH_HOST} ${_lookup})
  _test=$?

  if [[ ${_dns} != "${AUTH_HOST}" ]]; then
    _error=44
    log "Error ${_error}: result was ${_test}: ${_dns}"
    return ${_error}
  fi
}

##################################################################################

function download() {
  local           _attempts=5
  local              _error=0
  local _http_range_enabled   # TODO:40 OPTIMIZATION: disabled '--continue-at -'
  local               _loop=0
  local             _output
  local              _sleep=2

  if [[ -z ${1} ]]; then
    _error=33
    log "Error ${_error}: no URL to download!"
    exit ${_error}
  fi

  while true ; do
    (( _loop++ ))
    log "${1}..."
    _output=''
    curl ${CURL_OPTS} ${_http_range_enabled} --remote-name --location ${1}
    _output=$?
    #DEBUG=1; if [[ ${DEBUG} ]]; then log "DEBUG: curl exited ${_output}."; fi

    if (( ${_output} == 0 )); then
      log "Success: ${1##*/}"
      break
    fi

    if (( ${_loop} == ${_attempts} )); then
      _error=11
      log "Error ${_error}: couldn't download from: ${1}, giving up after ${_loop} tries."
      exit ${_error}
    elif (( ${_output} == 33 )); then
      log "Web server doesn't support HTTP range command, purging and falling back."
      _http_range_enabled=''
      rm -f ${1##*/}
    else
      log "${_loop}/${_attempts}: curl=${_output} ${1##*/} sleep ${_sleep}..."
      sleep ${_sleep}
    fi
  done
}

##################################################################################

function fileserver() {
  local    _action=${1} # REQUIRED
  local      _host=${2} # REQUIRED, TODO: default to PE?
  local      _port=${3} # OPTIONAL
  local _directory=${4} # OPTIONAL

  if [[ -z ${1} ]]; then
    _error=38
    log "Error ${_error}: start or stop action required!"
    exit ${_error}
  fi
  if [[ -z ${2} ]]; then
    _error=39
    log "Error ${_error}: host required!"
    exit ${_error}
  fi
  if [[ -z ${3} ]]; then
    _port=8181
  fi
  if [[ -z ${4} ]]; then
    _directory=cache
  fi

  case ${_action} in
    'start' )
      # Determine if on PE or PC with _host PE or PC, then _host=localhost
      # ssh -nNT -R 8181:localhost:8181 nutanix@10.21.31.31
      pushd ${_directory} || exit

      remote_exec 'ssh' ${_host} \
        "python -m SimpleHTTPServer ${_port} || python -m http.server ${_port}"
      popd || exit
      ;;
    'stop' )
      remote_exec 'ssh' ${_host} \
        "kill -9 $(pgrep python -a | grep ${_port} | awk '{ print $1 }')" 'OPTIONAL'
      ;;
  esac
}

##################################################################################


function finish() {
  log "${0} ran for ${SECONDS} seconds._____________________"
  echo
}

##################################################################################


function images() {
  # https://portal.nutanix.com/#/page/docs/details?targetId=Command-Ref-AOS-v59:acl-acli-image-auto-r.html
  local         _cli='nuclei'
  local     _command
  local   _http_body
  local       _image
  local  _image_type
  local        _name
  local      _source='source_uri'
  local        _test

#######################################
# For doing ISO IMAGES
#######################################

for _image in "${ISO_IMAGES[@]}" ; do

  # log "DEBUG: ${_image} image.create..."
  if [[ ${_cli} == 'nuclei' ]]; then
    _test=$(source /etc/profile.d/nutanix_env.sh \
      && ${_cli} image.list 2>&1 \
      | grep -i complete \
      | grep "${_image}")
  #else
  #  _test=$(source /etc/profile.d/nutanix_env.sh \
  #    && ${_cli} image.list 2>&1 \
  #    | grep "${_image}")
  fi

  if [[ ! -z ${_test} ]]; then
    log "Skip: ${_image} already complete on cluster."
  else
    _command=''
       _name="${_image}"

    if (( $(echo "${_image}" | grep -i -e '^http' -e '^nfs' | wc -l) )); then
      log 'Bypass multiple repo source checks...'
      SOURCE_URL="${_image}"
    else
      repo_source QCOW2_REPOS[@] "${_image}" # IMPORTANT: don't ${dereference}[array]!
    fi

    if [[ -z "${SOURCE_URL}" ]]; then
      _error=30
      log "Warning ${_error}: didn't find any sources for ${_image}, continuing..."
      # exit ${_error}
    fi

    # TODO:0 TOFIX: acs-centos ugly override for today...
    if (( $(echo "${_image}" | grep -i 'acs-centos' | wc -l ) > 0 )); then
      _name=acs-centos
    fi

    if [[ ${_cli} == 'acli' ]]; then
      _image_type='kIsoImage'
      _command+=" ${_name} annotation=${_image} image_type=${_image_type} \
        container=${STORAGE_IMAGES} architecture=kX86_64 wait=true"
    else
      _command+=" name=${_name} description=\"${_image}\""
    fi

    if [[ ${_cli} == 'nuclei' ]]; then
      _http_body=$(cat <<EOF
{"action_on_failure":"CONTINUE",
"execution_order":"SEQUENTIAL",
"api_request_list":[
{"operation":"POST",
"path_and_params":"/api/nutanix/v3/images",
"body":{"spec":
{"name":"${_name}","description":"${_image}","resources":{
  "image_type":"ISO_IMAGE",
  "source_uri":"${SOURCE_URL}"}},
"metadata":{"kind":"image"},"api_version":"3.1.0"}}],"api_version":"3.0"}
EOF
      )
      _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
        https://localhost:9440/api/nutanix/v3/batch)
      log "batch _test=|${_test}|"
    else

      ${_cli} "image.create ${_command}" ${_source}=${SOURCE_URL} 2>&1 &
      if (( $? != 0 )); then
        log "Warning: Image submission: $?. Continuing..."
        #exit 10
      fi

      if [[ ${_cli} == 'nuclei' ]]; then
        log "NOTE: image.uuid = RUNNING, but takes a while to show up in:"
        log "TODO: ${_cli} image.list, state = COMPLETE; image.list Name UUID State"
      fi
    fi
  fi

done

#######################################
# For doing Disk IMAGES
#######################################

  for _image in "${QCOW2_IMAGES[@]}" ; do

    # log "DEBUG: ${_image} image.create..."
    if [[ ${_cli} == 'nuclei' ]]; then
      _test=$(source /etc/profile.d/nutanix_env.sh \
        && ${_cli} image.list 2>&1 \
        | grep -i complete \
        | grep "${_image}")

    fi

    if [[ ! -z ${_test} ]]; then
      log "Skip: ${_image} already complete on cluster."
    else
      _command=''
         _name="${_image}"

      if (( $(echo "${_image}" | grep -i -e '^http' -e '^nfs' | wc -l) )); then
        log 'Bypass multiple repo source checks...'
        SOURCE_URL="${_image}"
      else
        repo_source QCOW2_REPOS[@] "${_image}" # IMPORTANT: don't ${dereference}[array]!
      fi

      if [[ -z "${SOURCE_URL}" ]]; then
        _error=30
        log "Warning ${_error}: didn't find any sources for ${_image}, continuing..."
        # exit ${_error}
      fi

      # TODO:0 TOFIX: acs-centos ugly override for today...
      if (( $(echo "${_image}" | grep -i 'acs-centos' | wc -l ) > 0 )); then
        _name=acs-centos
      fi

      if [[ ${_cli} == 'acli' ]]; then
        _image_type='kDiskImage'
        _command+=" ${_name} annotation=${_image} image_type=${_image_type} \
          container=${STORAGE_IMAGES} architecture=kX86_64 wait=true"
      else
        _command+=" name=${_name} description=\"${_image}\""
      fi

      if [[ ${_cli} == 'nuclei' ]]; then
        _http_body=$(cat <<EOF
{"action_on_failure":"CONTINUE",
"execution_order":"SEQUENTIAL",
"api_request_list":[
  {"operation":"POST",
  "path_and_params":"/api/nutanix/v3/images",
  "body":{"spec":
  {"name":"${_name}","description":"${_image}","resources":{
    "image_type":"DISK_IMAGE",
    "source_uri":"${SOURCE_URL}"}},
  "metadata":{"kind":"image"},"api_version":"3.1.0"}}],"api_version":"3.0"}
EOF
        )
        _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
          https://localhost:9440/api/nutanix/v3/batch)
        log "batch _test=|${_test}|"
      else

        ${_cli} "image.create ${_command}" ${_source}=${SOURCE_URL} 2>&1 &
        if (( $? != 0 )); then
          log "Warning: Image submission: $?. Continuing..."
          #exit 10
        fi

        if [[ ${_cli} == 'nuclei' ]]; then
          log "NOTE: image.uuid = RUNNING, but takes a while to show up in:"
          log "TODO: ${_cli} image.list, state = COMPLETE; image.list Name UUID State"
        fi
      fi
    fi

  done

}

##################################################################################
# Priority Images that need to be uploaded and controlled before we move to the mass upload

function priority_images(){

  local _prio_images_arr=(\
          ERA-Server-build-1.2.0.1.qcow2 \
          Windows2016.qcow2 \
          CentOS7.qcow2 \
          Citrix_Virtual_Apps_and_Desktops_7_1912.iso \
          )
  local CURL_HTTP_OPTS=" --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure "

  # Set the correct High Perf FileServer
  if [[ ${OCTET[1]} == '42' ]] || [[ ${OCTET[1]} == '38' ]]; then
    SOURCE_URL="10.42.38.10/images"
  else
    SOURCE_URL="10.55.76.10"
  fi

  log "Grabbing the priority files from the ${SOURCE_URL} fileserver..."

  for _image in "${_prio_images_arr[@]}"; do
    if [[ ${_image} == *"iso"* ]]; then
        DISK_TYPE="ISO_IMAGE"
    else
        DISK_TYPE="DISK_IMAGE"
    fi
    _http_body=$(cat <<EOF
{"action_on_failure":"CONTINUE",
"execution_order":"SEQUENTIAL",
"api_request_list":[
  {"operation":"POST",
  "path_and_params":"/api/nutanix/v3/images",
  "body":{"spec":
  {"name":"${_image}","description":"${_image}","resources":{
    "image_type":"${DISK_TYPE}",
    "source_uri":"http://${SOURCE_URL}/${_image}"}},
  "metadata":{"kind":"image"},"api_version":"3.1.0"}}],"api_version":"3.0"}
EOF
    )
  _task_id=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" https://localhost:9440/api/nutanix/v3/batch| jq '.api_response_list[].api_response.status.execution_context.task_uuid' | tr -d \")
  loop ${_task_id}

  done

}

##################################################################################

function log() {
  local _caller

  _caller=$(echo -n "$(caller 0 | awk '{print $2}')")
  echo "$(date '+%Y-%m-%d %H:%M:%S')|$$|${_caller}|${1}"
}

##################################################################################


function ntnx_cmd() {
  local _attempts=25
  local    _error=10
  local     _hold
  local     _loop=0
  local    _sleep=10
  local   _status

  while [[ true ]]; do
    (( _loop++ ))
      _hold=$(source /etc/profile ; nuclei cluster.list 2>&1)
    _status=$?

    if (( $(echo "${_hold}" | grep websocket | wc -l) > 0 )); then
      log "Warning: Zookeeper isn't up yet."
    elif (( ${_status} > 0 )); then
       log "${_status} = ${_hold}, uh oh!"
    else
      log "Cluster info via nuclei seems good: ${_status}, moving on!"
      break
    fi

    if (( ${_loop} == ${_attempts} )); then
      log "Error ${_error}: couldn't determine cluster information, giving up after ${_loop} tries."
      exit ${_error}
    else
      log "${_loop}/${_attempts}: hold=${_hold} sleep ${_sleep}..."
      sleep ${_sleep}
    fi
  done
}

##################################################################################


function ntnx_download() {
  local          _checksum
  local             _error
  local          _meta_url
  local _ncli_softwaretype="${1}"
  local        _source_url

  case "${_ncli_softwaretype}" in
    PC | pc | PRISM_CENTRAL_DEPLOY )
      args_required 'PC_VERSION'

      if [[ "${PC_VERSION}" == "${PC_DEV_VERSION}" ]]; then
        _meta_url="${PC_DEV_METAURL}"
        _source_url="${PC_DEV_URL}"
      elif [[ "${PC_VERSION}" == "${PC_CURRENT_VERSION}" ]]; then
        _meta_url="${PC_CURRENT_METAURL}"
        _source_url="${PC_CURRENT_URL}"
      else
        _meta_url="${PC_STABLE_METAURL}"
        _source_url="${PC_STABLE_URL}"
      fi

      #if [[ -z ${_meta_url} ]]; then
      #  _error=22
      #  log "Error ${_error}: unsupported PC_VERSION=${PC_VERSION}!"
      #  log 'Sync the following to global.var.sh...'
      #  log 'Browse to https://portal.nutanix.com/#/page/releases/prismDetails'
      #  log " - Find ${PC_VERSION} in the Additional Releases section on the lower right side"
      #  log ' - Provide the metadata URL for the "PC 1-click deploy from PE" option to this function, both case stanzas.'
      #  exit ${_error}
      #fi

      #if [[ ! -z ${PC_URL} ]]; then
      #  _source_url="${PC_URL}"
      #fi
      ;;
    'NOS' | 'nos' | 'AOS' | 'aos')
      # TODO:70 nos is a prototype
      args_required 'AOS_VERSION AOS_UPGRADE'
      _meta_url="${AOS_METAURL}"

      if [[ -z ${_meta_url} ]]; then
        _error=23
        log "Error ${_error}: unsupported AOS_UPGRADE=${AOS_UPGRADE}!"
        log 'Browse to https://portal.nutanix.com/#/page/releases/nosDetails'
        log " - Find ${AOS_UPGRADE} in the Additional Releases section on the lower right side"
        log ' - Provide the Upgrade metadata URL to this function for both case stanzas.'
        exit ${_error}
      fi

      if [[ ! -z ${AOS_URL} ]]; then
        _source_url="${AOS_URL}"
      fi
    ;;
    FILES | files | AFS | afs )
      args_required 'FILES_VERSION'
      _meta_url="${FILES_METAURL}"

      if [[ -z ${_meta_url} ]]; then
        _error=22
        log "Error ${_error}: unsupported FILES_VERSION=${FILES_VERSION}!"
        log 'Sync the following to global.var.sh...'
        log 'Browse to https://portal.nutanix.com/#/page/releases/afsDetails?targetVal=GA'
        log " - Find ${FILES_VERSION} in the Additional Releases section on the lower right side"
        log ' - Provide the metadata URL option to this function, both case stanzas.'
        exit ${_error}
      fi

      if [[ ! -z ${FILES_URL} ]]; then
        _source_url="${FILES_URL}"
      fi
    ;;
    FILE_ANALYTICS | file_analytics )
      args_required 'FILE_ANALYTICS_VERSION'
      _meta_url="${FILE_ANALYTICS_METAURL}"

      if [[ -z ${_meta_url} ]]; then
        _error=22
        log "Error ${_error}: unsupported FILES_VERSION=${FILE_ANALYTICS_VERSION}!"
        log 'Sync the following to global.var.sh...'
        log 'Browse to https://portal.nutanix.com/#/page/releases/afsDetails?targetVal=GA'
        log " - Find ${FILE_ANALYTICS_VERSION} in the Additional Releases section on the lower right side"
        log ' - Provide the metadata URL option to this function, both case stanzas.'
        exit ${_error}
      fi

      if [[ ! -z ${FILE_ANALYTICS_URL} ]]; then
        _source_url="${FILE_ANALYTICS_URL}"
      fi
    ;;
    * )
      _error=88
      log "Error ${_error}:: couldn't determine software-type ${_ncli_softwaretype}!"
      exit ${_error}
    ;;
  esac

  if [[ ! -e ${_meta_url##*/} ]]; then
    log "Retrieving download metadata ${_meta_url##*/} ..."
    download "${_meta_url}"
  else
    log "Warning: using cached download ${_meta_url##*/}"
  fi

  if [[ -z ${_source_url} ]]; then
    dependencies 'install' 'jq' || exit 13
    _source_url=$(cat ${_meta_url##*/} | jq -r .download_url_cdn)
  fi

  if (( $(pgrep curl | wc -l | tr -d '[:space:]') > 0 )); then
    pkill curl
  fi
  log "Retrieving Nutanix ${_ncli_softwaretype} bits..."
  download "${_source_url}"

  _checksum=$(md5sum ${_source_url##*/} | awk '{print $1}')
  if [[ $(cat ${_meta_url##*/} | jq -r .hex_md5) != "${_checksum}" ]]; then

    _error=2
    log "Error ${_error}: md5sum ${_checksum} doesn't match on: ${_source_url##*/} removing and exit!"
    rm -f ${_source_url##*/}
    exit ${_error}
  else
    log "Success: ${_ncli_softwaretype} bits downloaded and passed MD5 checksum!"
  fi

  ncli software upload software-type=${_ncli_softwaretype} \
         file-path="$(pwd)/${_source_url##*/}" \
    meta-file-path="$(pwd)/${_meta_url##*/}"

  if (( $? == 0 )) ; then
    log "Success! Delete ${_ncli_softwaretype} sources to free CVM space..."
    rm -f ${_source_url##*/} ${_meta_url##*/}
  else
    _error=3
    log "Error ${_error}: failed ncli upload of ${_ncli_softwaretype}."
    exit ${_error}
  fi
}

##################################################################################


function pe_determine() {
  # ${1} REQUIRED: run on 'PE' or 'PC'
  local _error
  local  _hold

  dependencies 'install' 'jq'

  # ncli @PE and @PC yeild different info! So PC uses nuclei.
  case ${1} in
    PE | pe )
      _hold=$(source /etc/profile.d/nutanix_env.sh \
        && ncli --json=true cluster info)
      ;;
    PC | Pc | pc )
      # WORKAROUND: Entities non-JSON outputs by nuclei on lines 1-2...
      _hold=$(source /etc/profile.d/nutanix_env.sh \
        && export   NUCLEI_SERVER='localhost' \
        && export NUCLEI_USERNAME="${PRISM_ADMIN}" \
        && export NUCLEI_PASSWORD="${PE_PASSWORD}" \
        && nuclei cluster.list format=json 2>/dev/null \
        | grep -v 'Entities :' \
        | jq \
        '.entities[].status | select(.state == "COMPLETE") | select(.resources.network.external_ip != null)'
      )
      ;;
    *)
      log 'Error: invoke with PC or PE argument.'
      ;;
  esac

  #log "DEBUG: cluster info on ${1}. |${_hold}|"

  if [[ -z "${_hold}" ]]; then
    _error=12
    log "Error ${_error}: couldn't resolve cluster info on ${1}. |${_hold}|"
    args_required 'PE_HOST'
    exit ${_error}
  else
    case ${1} in
      PE | pe )
        CLUSTER_NAME=$(echo ${_hold} | jq -r .data.name)
             PE_HOST=$(echo ${_hold} | jq -r .data.clusterExternalIPAddress)
        ;;
      PC | Pc | pc )
        CLUSTER_NAME=$(echo ${_hold} | jq -r .name)
             PE_HOST=$(echo ${_hold} | jq -r .resources.network.external_ip)
        ;;
    esac

    export CLUSTER_NAME PE_HOST
    log "Success: Cluster name=${CLUSTER_NAME}, PE external IP=${PE_HOST}"
  fi
}

##################################################################################


function prism_check {
  # Argument ${1} = REQUIRED: PE or PC
  # Argument ${2} = OPTIONAL: number of attempts
  # Argument ${3} = OPTIONAL: number of seconds per cycle

  args_required 'ATTEMPTS PE_PASSWORD SLEEP'

  local _attempts=${ATTEMPTS}
  local    _error=77
  local     _host
  local     _loop=0
  local _password="${PE_PASSWORD}"
  local  _pw_init='Nutanix/4u'
  local    _sleep=${SLEEP}
  local     _test=0

  #shellcheck disable=2153
  if [[ ${1} == 'PC' ]]; then
    _host=${PC_HOST}
  else
    _host=${PE_HOST}
  fi
  if [[ ! -z ${2} ]]; then
    _attempts=${2}
  fi

  while true ; do
    (( _loop++ ))
    _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${_password} \
      -X POST --data '{ "kind": "cluster" }' \
      https://${_host}:9440/api/nutanix/v3/clusters/list \
      | tr -d \") # wonderful addition of "" around HTTP status code by cURL

    if [[ ! -z ${3} ]]; then
      _sleep=${3}
    fi

    if (( ${_test} == 401 )); then
      log "Warning: unauthorized ${1} user or password on ${_host}."

      if [[ ${1} == 'PC' && ${_password} != "${_pw_init}" ]]; then
        _password=${_pw_init}
        log "Warning @${1}: Fallback on ${_host}: try initial password next cycle..."
        #_sleep=0 #break
      elif [[ ${1} == 'PC' && ${_password} == "${_pw_init}" && ${PC_VERSION} == "${PC_DEV_VERSION}" ]]; then
        _password=${PE_PASSWORD}
        log "Warning @${1}-dev: Fallback on ${_host}: try PE cluster password next cycle..."
        #_sleep=0 #break
      fi

    fi

    if (( ${_test} == 200 )); then
      log "@${1}: successful."
      return 0
    elif (( ${_loop} > ${_attempts} )); then
      log "Warning ${_error} @${1}: Giving up after ${_loop} tries."
      return ${_error}
    else
      log "@${1} ${_loop}/${_attempts}=${_test}: sleep ${_sleep} seconds..."
      sleep ${_sleep}
    fi
  done
}

##################################################################################


function remote_exec() {
# Argument ${1} = REQUIRED: ssh or scp
# Argument ${2} = REQUIRED: PE, PC, or AUTH_SERVER
# Argument ${3} = REQUIRED: command configuration
# Argument ${4} = OPTIONAL: populated with anything = allowed to fail

  local  _account='nutanix'
  local _attempts=3
  local    _error=99
  local     _host
  local     _loop=0
  local _password="${PE_PASSWORD}"
  local  _pw_init="${NTNX_INIT_PASSWORD}"
  local    _sleep=${SLEEP}
  local     _test=0

  args_required 'SSH_OPTS'

  # shellcheck disable=SC2153
  case ${2} in
    'PE' )
          _host=${PE_HOST}
      ;;
    'PC' )
          _host=${PC_HOST}
      _password=${_pw_init}
      ;;
    'AUTH_SERVER' )
       _account='root'
          _host=${AUTH_HOST}
      _password=${_pw_init}
         _sleep=7
      ;;
  esac

  if [[ -z ${3} ]]; then
    log 'Error ${_error}: missing third argument.'
    exit ${_error}
  fi

  if [[ ! -z ${4} ]]; then
    _attempts=1
       _sleep=0
  fi

  while true ; do
    (( _loop++ ))
    case "${1}" in
      'SSH' | 'ssh')
       #DEBUG=1; if [[ ${DEBUG} ]]; then log "_test will perform ${_account}@${_host} ${3}..."; fi
        SSHPASS="${_password}" sshpass -e ssh -x ${SSH_OPTS} ${_account}@${_host} "${3}"
        _test=$?
        ;;
      'SCP' | 'scp')
        #DEBUG=1; if [[ ${DEBUG} ]]; then log "_test will perform scp ${3} ${_account}@${_host}:"; fi
        SSHPASS="${_password}" sshpass -e scp ${SSH_OPTS} ${3} ${_account}@${_host}:
        _test=$?
        ;;
      *)
        log "Error ${_error}: improper first argument, should be ssh or scp."
        exit ${_error}
        ;;
    esac

    if (( ${_test} > 0 )) && [[ -z ${4} ]]; then
      _error=22
      log "Error ${_error}: pwd=$(pwd), _test=${_test}, _host=${_host}"
      exit ${_error}
    fi

    if (( ${_test} == 0 )); then
      if [[ ${DEBUG} ]]; then log "${3} executed properly."; fi
      return 0
    elif (( ${_loop} == ${_attempts} )); then
      if [[ -z ${4} ]]; then
        _error=11
        log "Error ${_error}: giving up after ${_loop} tries."
        exit ${_error}
      else
        log "Optional: giving up."
        break
      fi
    else
      log "${_loop}/${_attempts}: _test=$?|${_test}| SLEEP ${_sleep}..."
      sleep ${_sleep}
    fi
  done
}

##################################################################################


function repo_source() {
  # https://stackoverflow.com/questions/1063347/passing-arrays-as-parameters-in-bash#4017175
  local _candidates=("${!1}") # REQUIRED
  local    _package="${2}"    # OPTIONAL
  local      _error=29
  local  _http_code
  local      _index=0
  local     _suffix
  local        _url

  if (( ${#_candidates[@]} == 0 )); then
    log "Error ${_error}: Missing array!"
    exit ${_error}
  # else
  #   log "DEBUG: _candidates count is ${#_candidates[@]}"
  fi

  if [[ -z ${_package} ]]; then
    _suffix=${_candidates[0]##*/}
    if (( $(echo "${_suffix}" | grep . | wc -l) > 0)); then
      log "Convenience: omitted package argument, added package=${_package}"
      _package="${_suffix}"
    fi
  fi
  # Prepend your local HTTP cache...
  #_candidates=( "http://${HTTP_CACHE_HOST}:${HTTP_CACHE_PORT}/" "${_candidates[@]}" )

  while (( ${_index} < ${#_candidates[@]} ))
  do
    echo ${_candidates[${_index}]}
    unset SOURCE_URL

    # log "DEBUG: ${_index} ${_candidates[${_index}]}, OPTIONAL: _package=${_package}"
    _url=${_candidates[${_index}]}

    if [[ -z ${_package} ]]; then
      if (( $(echo "${_url}" | grep '/$' | wc -l) == 0 )); then
        log "error ${_error}: ${_url} doesn't end in trailing slash, please correct."
        exit ${_error}
      fi
    elif (( $(echo "${_url}" | grep '/$' | wc -l) == 1 )); then
      _url+="${_package}"
    fi

    if (( $(echo "${_url}" | grep '^nfs' | wc -l) == 1 )); then
      log "warning: TODO: cURL can't test nfs URLs...assuming a pass!"
      export SOURCE_URL="${_url}"
      break
    fi

    _http_code=$(curl ${CURL_OPTS} --max-time 5 --write-out '%{http_code}' --head ${_url} | tail -n1)

    if [[ (( ${_http_code} == 200 )) || (( ${_http_code} == 302 )) ]]; then
      export SOURCE_URL="${_url}"
      log "Found, HTTP:${_http_code} = ${SOURCE_URL}"
      break
    fi
    log " Lost, HTTP:${_http_code} = ${_url}"
    ((_index++))
  done

  if [[ -z "${SOURCE_URL}" ]]; then
    _error=30
    log "Error ${_error}: didn't find any sources, last try was ${_url} with HTTP ${_http_code}."
    exit ${_error}
  fi
}

##################################################################################


function run_once() {
  # Try to login to the PC UI using an API and use the NEW to be password so we can check if PC config has run....
  _Configured_PC=$(curl -X POST https://${PC_HOST}:9440/api/nutanix/v3/clusters/list --user ${PRISM_ADMIN}:${PE_PASSWORD}  -H 'Content-Type: application/json' -d '{ "kind": "cluster" }' --insecure --silent | grep "AUTHENTICATION_REQUIRED" | wc -l)
  if [[ $_Configured_PC -lt 1 ]]; then
    _error=2
    log "Warning ${_error}: ${PC_LAUNCH} already ran and configured PRISM Central, exit!"
    exit ${_error}
  fi
}

##################################################################################


function ssh_pubkey() {
  local         _dir
  local _directories=(\
     "${HOME}" \
     "${HOME}/ssh_keys" \
     "${HOME}/cache" \
   )
  local        _name
  local        _test

  args_required 'EMAIL SSH_PUBKEY'

  _name=${EMAIL//\./_DOT_}
  _name=${_name/@/_AT_}
  _test=$(source /etc/profile.d/nutanix_env.sh \
    && ncli cluster list-public-keys name=${_name})

  if (( $(echo ${_test} | grep -i "Failed" | wc ${WC_ARG}) > 0 )); then
    for _dir in "${_directories[@]}"; do
      if [[ -e ${_dir}/${SSH_PUBKEY##*/} ]]; then
        log "Note that a period and other symbols aren't allowed to be a key name."

        log "Locally adding ${_dir}/${SSH_PUBKEY##*/} under ${_name} label..."
        ncli cluster add-public-key name=${_name} file-path=${_dir}/${SSH_PUBKEY##*/} || true

        break
      fi
    done
  else
    log "IDEMPOTENCY: found pubkey ${_name}"
  fi
}

###############################################################################################################################################################################
# Routine to be run/loop till yes we are ok.
###############################################################################################################################################################################
# Need to grab the percentage_complete value including the status to make disissions

# TODO: Also look at the status!!

function loop(){

  local _attempts=45
  local _loops=0
  local _sleep=60
  local _url_progress='https://localhost:9440/api/nutanix/v3/tasks'
  local CURL_HTTP_OPTS=" --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure "

  echo ${_task_id}
  # What is the progress of the taskid??
  while true; do
    (( _loops++ ))
    # Get the progress of the task
    _progress=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} ${_url_progress}/${_task_id} | jq '.percentage_complete' 2>nul | tr -d \")

    if (( ${_progress} == 100 )); then
      log "The step has been succesfuly run"
      break;
    elif (( ${_loops} > ${_attempts} )); then
      log "Warning ${_error} @${1}: Giving up after ${_loop} tries."
      return ${_error}
    else
      log "Still running... loop $_loops/$_attempts. Step is at ${_progress}% ...Sleeping ${_sleep} seconds"
      sleep ${_sleep}
    fi
  done
}
