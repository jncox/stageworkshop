#!/usr/bin/env bash
# -x
# Dependencies: curl, ncli, nuclei, jq

###############################################################################################################################################################################
# 12th of April 2019 - Willem Essenstam
# Added a "-d" character in the flow_enable so the command would run.
# Changed the Karbon Eanable function so it also checks that Karbon has been enabled. Some small typos changed so the Karbon part should work
#
# 31-05-2019 - Willem Essenstam
# Added the download bits for the Centos Image for Karbon
###############################################################################################################################################################################



###############################################################################################################################################################################
# Routine to enable Flow
###############################################################################################################################################################################

function flow_enable() {
  local _attempts=30
  local _loops=0
  local _sleep=60
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
  local _url_flow='https://localhost:9440/api/nutanix/v3/services/microseg'

  # Create the JSON payload
  _json_data='{"state":"ENABLE"}'

  log "Enable Nutanix Flow..."

  # Enabling Flow and put the task id in a variable
  _task_id=$(curl -X POST -d $_json_data $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} $_url_flow | jq '.task_uuid' | tr -d \")

  # Try one more time then fail, but continue
  if [ -z $_task_id ]; then
    log "Flow not yet enabled. Will retry...."
    _task_id=$(curl -X POST $_json_data $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} $_url_flow)

    if [ -z $_task_id ]; then
      log "Flow still not enabled.... ***Not retrying. Please enable via UI.***"
    fi
  else
    log "Flow has been Enabled..."
  fi



}

###############################################################################################################################################################################
# Routine to be run/loop till yes we are ok.
###############################################################################################################################################################################
# Need to grab the percentage_complete value including the status to make disissions

# TODO: Also look at the status!!

function loop(){

  local _attempts=40
  local _loops=0
  local _sleep=60
  local CURL_HTTP_OPTS=" --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure "

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

###############################################################################################################################################################################
# Routine to start the LCM Inventory and the update.
###############################################################################################################################################################################

function lcm() {

  local _url_lcm='https://localhost:9440/PrismGateway/services/rest/v1/genesis'
  local _url_progress='https://localhost:9440/api/nutanix/v3/tasks'
  local _url_groups='https://localhost:9440/api/nutanix/v3/groups'
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '

  # Inventory download/run
  _task_id=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d '{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"perform_inventory\",\"args\":[\"http://download.nutanix.com/lcm/2.0\"]}}"}' ${_url_lcm} | jq '.value' 2>nul | cut -d "\\" -f 4 | tr -d \")

  # If there has been a reply (task_id) then the URL has accepted by PC
  # Changed (()) to [] so it works....
  if [ -z "$_task_id" ]; then
       log "LCM Inventory start has encountered an eror..."
  else
       log "LCM Inventory started.."
       set _loops=0 # Reset the loop counter so we restart the amount of loops we need to run

       # Run the progess checker
       loop

       #################################################################
       # Grab the json from the possible to be updated UUIDs and versions and save local in reply_json.json
       #################################################################

       # Need loop so we can create the full json more dynamical

       # Issue is taht after the LCM inventory the LCM will be updated to a version 2.0 and the API call needs to change!!!
       # We need to figure out if we are running V1 or V2!
       lcm_version=$(curl $CURL_HTTP_OPTS --user $PRISM_ADMIN:$PE_PASSWORD -X POST -d '{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"get_config\"}}"}'  ${_url_lcm} | jq '.value' | tr -d \\ | sed 's/^"\(.*\)"$/\1/' | sed 's/.return/return/g' | jq '.return.lcm_cpdb_table_def_list.entity' | tr -d \"| grep "lcm_entity_v2" | wc -l)

       if [ $lcm_version -lt 1 ]; then
              log "LCM Version 1 found.."
              # V1: Run the Curl command and save the oputput in a temp file
              curl $CURL_HTTP_OPTS --user $PRISM_ADMIN:$PE_PASSWORD -X POST -d '{"entity_type": "lcm_available_version","grouping_attribute": "entity_uuid","group_member_count": 1000,"group_member_attributes": [{"attribute": "uuid"},{"attribute": "entity_uuid"},{"attribute": "entity_class"},{"attribute": "status"},{"attribute": "version"},{"attribute": "dependencies"},{"attribute": "order"}]}'  $_url_groups > reply_json.json

              # Fill the uuid array with the correct values
              uuid_arr=($(jq '.group_results[].entity_results[].data[] | select (.name=="entity_uuid") | .values[0].values[0]' reply_json.json | sort -u | tr "\"" " " | tr -s " "))

              # Grabbing the versions of the UUID and put them in a versions array
              for uuid in "${uuid_arr[@]}"
              do
                version_ar+=($(jq --arg uuid "$uuid" '.group_results[].entity_results[] | select (.data[].values[].values[0]==$uuid) | select (.data[].name=="version") | .data[].values[].values[0]' reply_json.json | tail -4 | head -n 1 | tr -d \"))
              done
        else
              log "LCM Version 2 found.."

              #''_V2: run the other V2 API call to get the UUIDs of the to be updated software parts
              # Grab the installed version of the software first UUIDs
              curl $CURL_HTTP_OPTS --user $PRISM_ADMIN:$PE_PASSWORD -X POST -d '{"entity_type": "lcm_entity_v2","group_member_count": 500,"group_member_attributes": [{"attribute": "id"}, {"attribute": "uuid"}, {"attribute": "entity_model"}, {"attribute": "version"}, {"attribute": "location_id"}, {"attribute": "entity_class"}, {"attribute": "description"}, {"attribute": "last_updated_time_usecs"}, {"attribute": "request_version"}, {"attribute": "_master_cluster_uuid_"}, {"attribute": "entity_type"}, {"attribute": "single_group_uuid"}],"query_name": "lcm:EntityGroupModel","grouping_attribute": "location_id","filter_criteria": "entity_model!=AOS;entity_model!=NCC;entity_model!=PC;_master_cluster_uuid_==[no_val]"}' $_url_groups > reply_json_uuid.json

              # Fill the uuid array with the correct values
              uuid_arr=($(jq '.group_results[].entity_results[].data[] | select (.name=="uuid") | .values[0].values[0]' reply_json_uuid.json | sort -u | tr "\"" " " | tr -s " "))

              # Grab the available updates from the PC after LCMm has run
              curl $CURL_HTTP_OPTS --user $PRISM_ADMIN:$PE_PASSWORD -X POST -d '{"entity_type": "lcm_available_version_v2","group_member_count": 500,"group_member_attributes": [{"attribute": "uuid"},{"attribute": "entity_uuid"}, {"attribute": "entity_class"}, {"attribute": "status"}, {"attribute": "version"}, {"attribute": "dependencies"},{"attribute": "single_group_uuid"}, {"attribute": "_master_cluster_uuid_"}, {"attribute": "order"}],"query_name": "lcm:VersionModel","filter_criteria": "_master_cluster_uuid_==[no_val]"}' $_url_groups > reply_json_ver.json

              # Grabbing the versions of the UUID and put them in a versions array
              for uuid in "${uuid_arr[@]}"
                do
                  # Get the latest version from the to be updated uuid
                  version_ar+=($(jq --arg uuid "$uuid" '.group_results[].entity_results[] | select (.data[].values[].values[]==$uuid) .data[] | select (.name=="version") .values[].values[]' reply_json_ver.json | tail -1 | tr -d \"))
                done
              # Copy the right info into the to be used array
        fi

       # Set the parameter to create the ugrade plan
       # Create the curl json string '-d blablablablabla' so we can call the string and not the full json data line
       # Begin of the JSON data payload
       _json_data="-d "
       _json_data+="{\"value\":\"{\\\".oid\\\":\\\"LifeCycleManager\\\",\\\".method\\\":\\\"lcm_framework_rpc\\\",\\\".kwargs\\\":{\\\"method_class\\\":\\\"LcmFramework\\\",\\\"method\\\":\\\"generate_plan\\\",\\\"args\\\":[\\\"http://download.nutanix.com/lcm/2.0\\\",["

       # Combine the two created UUID and Version arrays to the full needed data using a loop
       count=0
       while [ $count -lt ${#uuid_arr[@]} ]
       do
          if [[ ! -z ${version_ar[$count]} ]]
            _json_data+="[\\\"${uuid_arr[$count]}\\\",\\\"${version_ar[$count]}\\\"],"
            log "Found UUID ${uuid_arr[$count]} and version ${version_ar[$count]}"
          fi
          let count=count+1
        done

       # Remove the last "," as we don't need it.
       _json_data=${_json_data%?};

       # Last part of the JSON data payload
       _json_data+="]]}}\"}"

       # Run the generate plan task
       _task_id=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST $_json_data ${_url_lcm})

       # Notify the log server that the LCM has created a plan
       log "LCM Inventory has created a plan"

       # Reset the loop counter so we restart the amount of loops we need to run
       set _loops=0

       # As the new json for the perform the upgrade only needs to have "generate_plan" changed into "perform_update" we use sed...
       _json_data=$(echo $_json_data | sed -e 's/generate_plan/perform_update/g')


       # Run the upgrade to have the latest versions
       _task_id=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST $_json_data ${_url_lcm} | jq '.value' 2>nul | cut -d "\\" -f 4 | tr -d \")

       # If there has been a reply task_id then the URL has accepted by PC
        if [ -z "$_task_id" ]; then
            # There has been an error!!!
            log "LCM Upgrade has encountered an error!!!!"
        else
            # Notify the logserver that we are starting the LCM Upgrade
            log "LCM Upgrade starting...Process may take up to 40 minutes!!!"

            # Run the progess checker
            loop
        fi
  fi

  # Remove the temp json files as we don't need it anymore
       #rm -rf reply_json.json
       #rm -rf reply_json_ver.json
       #rm -rf reply_json_uuid.json

}

###############################################################################################################################################################################
# Routine to enable Karbon
###############################################################################################################################################################################

function karbon_enable() {
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
  local _loop=0
  local _json_data_set_enable="{\"value\":\"{\\\".oid\\\":\\\"ClusterManager\\\",\\\".method\\\":\\\"enable_service_with_prechecks\\\",\\\".kwargs\\\":{\\\"service_list_json\\\":\\\"{\\\\\\\"service_list\\\\\\\":[\\\\\\\"KarbonUIService\\\\\\\",\\\\\\\"KarbonCoreService\\\\\\\"]}\\\"}}\"}"
  local _json_is_enable="{\"value\":\"{\\\".oid\\\":\\\"ClusterManager\\\",\\\".method\\\":\\\"is_service_enabled\\\",\\\".kwargs\\\":{\\\"service_name\\\":\\\"KarbonUIService\\\"}}\"} "
  local _httpURL="https://localhost:9440/PrismGateway/services/rest/v1/genesis"

  # Start the enablement process
  _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_set_enable ${_httpURL}| grep "[true, null]" | wc -l)

  # Check if we got a "1" back (start sequence received). If not, retry. If yes, check if enabled...
  if [[ $_response -eq 1 ]]; then
    # Check if Karbon has been enabled
    _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_is_enable ${_httpURL}| grep "[true, null]" | wc -l)
    while [ $_response -ne 1 ]; do
        _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_is_enable ${_httpURL}| grep "[true, null]" | wc -l)
    done
    log "Karbon has been enabled."
  else
    log "Retrying to enable Karbon one more time."
    _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_set_enable ${_httpURL}| grep "[true, null]" | wc -l)
    if [[ $_response -eq 1 ]]; then
      _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_is_enable ${_httpURL}| grep "[true, null]" | wc -l)
      if [ $_response -lt 1 ]; then
        log "Karbon isn't enabled. Please use the UI to enable it."
      else
        log "Karbon has been enabled."
      fi
    fi
  fi
}

###############################################################################################################################################################################
# Download Karbon CentOS Image
###############################################################################################################################################################################

function karbon_image_download() {
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
  local _loop=0
  local _startDownload="https://localhost:7050/acs/image/download"
  local _getuuidDownload="https://localhost:7050/acs/image/list"

  # Create the Basic Authentication using base6 commands
  _auth=$(echo "admin:${PE_PASSWORD}" | base64)

  # Call the UUID URL so we have the right UUID for the image
  uuid=$(curl -X GET -H "X-NTNX-AUTH: Basic ${_auth}" https://localhost:7050/acs/image/list $CURL_HTTP_OPTS | jq '.[0].uuid' | tr -d \/\")
  log "UUID for The Karbon image is: $uuid"

  # Use the UUID to download the image
  response=$(curl -X POST ${_startDownload} -d "{\"uuid\":\"${uuid}\"}" -H "X-NTNX-AUTH: Basic ${_auth}" ${CURL_HTTP_OPTS})

  if [ -z $response ]; then
    log "Download of the CenOS image for Karbon has not been started. Trying one more time..."
    response=$(curl -X POST ${_startDownload} -d "{\"uuid\":\"${uuid}\"}" -H "X-NTNX-AUTH: Basic ${_auth}" ${CURL_HTTP_OPTS})
    if [ -z $response ]; then
      log "Download of CentOS image for Karbon failed... Please run manually."
    fi
  else
    log "Download of CentOS image for Karbon has started..."
  fi
}

###############################################################################################################################################################################
# Routine to enable Objects
###############################################################################################################################################################################

function objects_enable() {
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
  local _loops=0
  local _json_data_set_enable="{\"state\":\"ENABLE\"}"
  local _json_data_check="{\"entity_type\":\"objectstore\"}"
  local _httpURL_check="https://localhost:9440/oss/api/nutanix/v3/groups"
  local _httpURL="https://localhost:9440/api/nutanix/v3/services/oss"

  # Start the enablement process
  _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_set_enable ${_httpURL})
  log "Enabling Objects....."

  # The response should be a Task UUID
  if [[ ! -z $_response ]]; then
    # Check if OSS has been enabled
    _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_check ${_httpURL_check}| grep "objectstore" | wc -l)
    while [ $_response -ne 1 ]; do
        _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_check ${_httpURL_check}| grep "objectstore" | wc -l)
        if [[ $loops -ne 30 ]]; then
          sleep 10
          (( _loops++ ))
        else
          log "Objects isn't enabled. Please use the UI to enable it."
          break
        fi
    done
    log "Objects has been enabled."
  else
    log "Objects isn't enabled. Please use the UI to enable it."
  fi
}

###############################################################################################################################################################################
# Create an object store called ntnx_object.ntnxlab.local
###############################################################################################################################################################################

function object_store() {
    local _attempts=30
    local _loops=0
    local _sleep=60
    local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
    local _url_network='https://localhost:9440/api/nutanix/v3/subnets/list'
    local _url_oss='https://localhost:9440/oss/api/nutanix/v3/objectstores'

    # Payload for the _json_data
    _json_data='{"kind":"subnet"}'

    # Get the json data and split into CLUSTER_UUID and Primary_Network_UUID
    CLUSTER_UUID=$(curl -X POST -d $_json_data $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} $_url_network | jq '.entities[].spec | select (.name=="Primary") | .cluster_reference.uuid' | tr -d \")
    echo ${CLUSTER_UUID}

    PRIM_NETWORK_UUID=$(curl -X POST -d $_json_data $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} $_url_network | jq '.entities[] | select (.spec.name=="Primary") | .metadata.uuid' | tr -d \")
    echo ${PRIM_NETWORK_UUID}

    _json_data_oss='{"api_version":"3.0","metadata":{"kind":"objectstore"},"spec":{"name":"ntnx-objects","description":"NTNXLAB","resources":{"domain":"ntnxlab.local","cluster_reference":{"kind":"cluster","uuid":"'
    _json_data_oss+=${CLUSTER_UUID}
    _json_data_oss+='"},"buckets_infra_network_dns":"NETWORKX.VLANX.16","buckets_infra_network_vip":"NETWORKX.VLANX.17","buckets_infra_network_reference":{"kind":"subnet","uuid":"'
    _json_data_oss+=${PRIM_NETWORK_UUID}
    _json_data_oss+='"},"client_access_network_reference":{"kind":"subnet","uuid":"'
    _json_data_oss+=${PRIM_NETWORK_UUID}
    _json_data_oss+='"},"aggregate_resources":{"total_vcpu_count":10,"total_memory_size_mib":32768,"total_capacity_gib":51200},"client_access_network_ipv4_range":{"ipv4_start":"NETWORKX.VLANX.18","ipv4_end":"NETWORKX.VLANX.21"}}}}'

    # Set the right VLAN dynamically so we are configuring in the right network
    _json_data_oss=${_json_data_oss//VLANX/${VLAN}}
    _json_data_oss=${_json_data_oss//NETWORKX/${NETWORK}}

    curl -X POST -d $_json_data_oss $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} $_url_oss

}


###############################################################################################################################################################################
# Routine for PC_Admin
###############################################################################################################################################################################

function pc_admin() {
  local  _http_body
  local       _test
  local _admin_user='marklavi'

  _http_body=$(cat <<EOF
  {"profile":{
    "username":"${_admin_user}",
    "firstName":"Mark",
    "lastName":"Lavi",
    "emailId":"${EMAIL}",
    "password":"${PE_PASSWORD}",
    "locale":"en-US"},"enabled":false,"roles":[]}
EOF
  )
  _test=$(curl ${CURL_HTTP_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/PrismGateway/services/rest/v1/users)
  log "create.user=${_admin_user}=|${_test}|"

  _http_body='["ROLE_USER_ADMIN","ROLE_MULTICLUSTER_ADMIN"]'
       _test=$(curl ${CURL_HTTP_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/PrismGateway/services/rest/v1/users/${_admin_user}/roles)
  log "add.roles ${_http_body}=|${_test}|"
}

###############################################################################################################################################################################
# Routine set PC authentication to use the AD as well
###############################################################################################################################################################################
function pc_auth() {
  # TODO:190 configure case for each authentication server type?
  local      _group
  local  _http_body
  local _pc_version
  local       _test

  # TODO:50 FUTURE: pass AUTH_SERVER argument

  log "Add Directory ${AUTH_SERVER}"
  _http_body=$(cat <<EOF
{"name":"${AUTH_SERVER}","domain":"${AUTH_FQDN}","directoryType":"ACTIVE_DIRECTORY","connectionType":"LDAP",
EOF
  )

  # shellcheck disable=2206
  _pc_version=(${PC_VERSION//./ })

  log "Checking if PC_VERSION ${PC_VERSION} >= 5.9"
  if (( ${_pc_version[0]} >= 5 && ${_pc_version[1]} >= 9 )); then
    _http_body+=$(cat <<EOF
"groupSearchType":"RECURSIVE","directoryUrl":"ldap://${AUTH_HOST}:${LDAP_PORT}",
EOF
)
  else
    _http_body+=" \"directoryUrl\":\"ldaps://${AUTH_HOST}/\","
  fi

  _http_body+=$(cat <<EOF
    "serviceAccountUsername":"${AUTH_ADMIN_USER}",
    "serviceAccountPassword":"${AUTH_ADMIN_PASS}"
  }
EOF
  )

  _test=$(curl ${CURL_POST_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/PrismGateway/services/rest/v1/authconfig/directories)
  log "directories: _test=|${_test}|_http_body=|${_http_body}|"

  log "Add Role Mappings to Groups for PC logins (not projects, which are separate)..."
  #TODO:20 hardcoded role mappings
  for _group in 'SSP Admins' 'SSP Power Users' 'SSP Developers' 'SSP Basic Users'; do
    _http_body=$(cat <<EOF
    {
      "directoryName":"${AUTH_SERVER}",
      "role":"ROLE_CLUSTER_ADMIN",
      "entityType":"GROUP",
      "entityValues":["${_group}"]
    }
EOF
    )
    _test=$(curl ${CURL_POST_OPTS} \
      --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
      https://localhost:9440/PrismGateway/services/rest/v1/authconfig/directories/${AUTH_SERVER}/role_mappings)
    log "Cluster Admin=${_group}, _test=|${_test}|"
  done
}

###############################################################################################################################################################################
# Routine to import the images into PC
###############################################################################################################################################################################

function pc_cluster_img_import() {
  local _http_body
  local      _test
  local      _uuid

       _uuid=$(source /etc/profile.d/nutanix_env.sh \
              && ncli --json=true cluster info \
              | jq -r .data.uuid)
  _http_body=$(cat <<EOF
{"action_on_failure":"CONTINUE",
 "execution_order":"SEQUENTIAL",
 "api_request_list":[{
   "operation":"POST",
   "path_and_params":"/api/nutanix/v3/images/migrate",
   "body":{
     "image_reference_list":[],
     "cluster_reference":{
       "uuid":"${_uuid}",
       "kind":"cluster",
       "name":"string"}}}],
 "api_version":"3.0"}
EOF
  )
  _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/api/nutanix/v3/batch)
  log "batch _test=|${_test}|"
}

###############################################################################################################################################################################
# Routine to add dns servers
###############################################################################################################################################################################

function pc_dns_add() {
  local _dns_server
  local       _test

  for _dns_server in $(echo "${DNS_SERVERS}" | sed -e 's/,/ /'); do
    _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "[\"$_dns_server\"]" \
      https://localhost:9440/PrismGateway/services/rest/v1/cluster/name_servers/add_list)
    log "name_servers/add_list |${_dns_server}| _test=|${_test}|"
  done
}

###############################################################################################################################################################################
# Routine to setup the initial steps for PC; NTP, EULA and Pulse
###############################################################################################################################################################################

function pc_init() {
  # TODO:130 pc_init: NCLI, type 'cluster get-smtp-server' config for idempotency?
  local _test

  log "Configure NTP@PC"
  ncli cluster add-to-ntp-servers \
    servers=0.us.pool.ntp.org,1.us.pool.ntp.org,2.us.pool.ntp.org,3.us.pool.ntp.org

  log "Validate EULA@PC"
  _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d '{
      "username": "SE",
      "companyName": "NTNX",
      "jobTitle": "SE"
  }' https://localhost:9440/PrismGateway/services/rest/v1/eulas/accept)
  log "EULA _test=|${_test}|"

  log "Disable Pulse@PC"
  _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X PUT -d '{
      "emailContactList":null,
      "enable":false,
      "verbosityType":null,
      "enableDefaultNutanixEmail":false,
      "defaultNutanixEmail":null,
      "nosVersion":null,
      "isPulsePromptNeeded":false,
      "remindLater":null
  }' https://localhost:9440/PrismGateway/services/rest/v1/pulse)
  log "PULSE _test=|${_test}|"
}

###############################################################################################################################################################################
# Routine to setup the SMTP server in PC
###############################################################################################################################################################################

function pc_smtp() {
  log "Configure SMTP@PC"
  local _sleep=5

  args_required 'SMTP_SERVER_ADDRESS SMTP_SERVER_FROM SMTP_SERVER_PORT'
  ncli cluster set-smtp-server port=${SMTP_SERVER_PORT} \
    address=${SMTP_SERVER_ADDRESS} from-email-address=${SMTP_SERVER_FROM}
  #log "sleep ${_sleep}..."; sleep ${_sleep}
  #log $(ncli cluster get-smtp-server | grep Status | grep success)

  # shellcheck disable=2153
  ncli cluster send-test-email recipient="${EMAIL}" \
    subject="pc_smtp https://${PRISM_ADMIN}:${PE_PASSWORD}@${PC_HOST}:9440 Testing."
  # local _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d '{
  #   "address":"${SMTP_SERVER_ADDRESS}","port":"${SMTP_SERVER_PORT}","username":null,"password":null,"secureMode":"NONE","fromEmailAddress":"${SMTP_SERVER_FROM}","emailStatus":null}' \
  #   https://localhost:9440/PrismGateway/services/rest/v1/cluster/smtp)
  # log "_test=|${_test}|"
}

###############################################################################################################################################################################
# Routine to change the PC admin password
###############################################################################################################################################################################

function pc_passwd() {
  args_required 'PRISM_ADMIN PE_PASSWORD'

  log "Reset PC password to PE password, must be done by ncli@PC, not API or on PE"
  ncli user reset-password user-name=${PRISM_ADMIN} password=${PE_PASSWORD}
  if (( $? > 0 )); then
   log "Warning: password not reset: $?."# exit 10
  fi
  # TOFIX: nutanix@PC Linux account password change as well?

  # local _old_pw='nutanix/4u'
  # local _http_body=$(cat <<EOF
  # {"oldPassword": "${_old_pw}","newPassword": "${PE_PASSWORD}"}
  # EOF
  # )
  # local _test
  # _test=$(curl ${CURL_HTTP_OPTS} --user "${PRISM_ADMIN}:${_old_pw}" -X POST --data "${_http_body}" \
  #     https://localhost:9440/PrismGateway/services/rest/v1/utils/change_default_system_password)
  # log "cURL reset password _test=${_test}"
}




###############################################################################################################################################################################
# Seed PC data for Prism Pro Labs
###############################################################################################################################################################################

function seedPC() {
    local _test
    local _setup

    _test=$(curl -L ${PC_DATA} -o /home/nutanix/seedPC.zip)
    log "Pulling Prism Data| PC_DATA ${PC_DATA}|${_test}"
    unzip /home/nutanix/seedPC.zip
    pushd /home/nutanix/lab/

    #_setup=$(/home/nutanix/lab/setupEnv.sh ${PC_HOST} > /dev/null 2>&1)
    _setup=$(/home/nutanix/lab/initialize_lab.sh ${PC_HOST} > /dev/null 2>&1)
    log "Running Setup Script|$_setup"

    popd
}

###############################################################################################################################################################################
# Routine to setp up the SSP authentication to use the AutoDC server
###############################################################################################################################################################################

function ssp_auth() {
  args_required 'AUTH_SERVER AUTH_HOST AUTH_ADMIN_USER AUTH_ADMIN_PASS'

  local   _http_body
  local   _ldap_name
  local   _ldap_uuid
  local _ssp_connect

  log "Find ${AUTH_SERVER} uuid"
  _ldap_uuid=$(PATH=${PATH}:${HOME}; curl ${CURL_POST_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} --data '{ "kind": "directory_service" }' \
    https://localhost:9440/api/nutanix/v3/directory_services/list \
    | jq -r .entities[0].metadata.uuid)
  log "_ldap_uuid=|${_ldap_uuid}|"

  # TODO:110 get directory service name _ldap_name
  _ldap_name=${AUTH_SERVER}
  # TODO:140 bats? test ldap connection

  log "Connect SSP Authentication (spec-ssp-authrole.json)..."
  _http_body=$(cat <<EOF
  {
    "spec": {
      "name": "${AUTH_SERVER}",
      "resources": {
        "admin_group_reference_list": [
          {
            "name": "cn=ssp developers,cn=users,dc=ntnxlab,dc=local",
            "uuid": "3933a846-fe73-4387-bb39-7d66f222c844",
            "kind": "user_group"
          }
        ],
        "service_account": {
          "username": "${AUTH_ADMIN_USER}",
          "password": "${AUTH_ADMIN_PASS}"
        },
        "url": "ldaps://${AUTH_HOST}/",
        "directory_type": "ACTIVE_DIRECTORY",
        "admin_user_reference_list": [],
        "domain_name": "${AUTH_DOMAIN}"
      }
    },
    "metadata": {
      "kind": "directory_service",
      "spec_version": 0,
      "uuid": "${_ldap_uuid}",
      "categories": {}
    },
    "api_version": "3.1.0"
  }
EOF
  )
  _ssp_connect=$(curl ${CURL_POST_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X PUT --data "${_http_body}" \
    https://localhost:9440/api/nutanix/v3/directory_services/${_ldap_uuid})
  log "_ssp_connect=|${_ssp_connect}|"

  # TODO:120 SSP Admin assignment, cluster, networks (default project?) = spec-project-config.json
  # PUT https://localhost:9440/api/nutanix/v3/directory_services/9d8c2c33-9d95-438c-a7f4-2187120ae99e = spec-ssp-direcory_service.json
  # TODO:60 FUTURE: use directory_type variable?
  log "Enable SSP Admin Authentication (spec-ssp-direcory_service.json)..."
  _http_body=$(cat <<EOF
  {
    "spec": {
      "name": "${_ldap_name}",
      "resources": {
        "service_account": {
          "username": "${AUTH_ADMIN_USER}@${AUTH_FQDN}",
          "password": "${AUTH_ADMIN_PASS}"
        },
        "url": "ldaps://${AUTH_HOST}/",
        "directory_type": "ACTIVE_DIRECTORY",
        "domain_name": "${AUTH_DOMAIN}"
      }
    },
    "metadata": {
      "kind": "directory_service",
      "spec_version": 0,
      "uuid": "${_ldap_uuid}",
      "categories": {}
    },
    "api_version": "3.1.0"
  }
EOF
  )
  _ssp_connect=$(curl ${CURL_POST_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X PUT --data "${_http_body}" \
    https://localhost:9440/api/nutanix/v3/directory_services/${_ldap_uuid})
  log "_ssp_connect=|${_ssp_connect}|"
  # POST https://localhost:9440/api/nutanix/v3/groups = spec-ssp-groups.json
  # TODO:100 can we skip previous step?
  log "Enable SSP Admin Authentication (spec-ssp-groupauth_2.json)..."
  _http_body=$(cat <<EOF
  {
    "spec": {
      "name": "${_ldap_name}",
      "resources": {
        "service_account": {
          "username": "${AUTH_ADMIN_USER}@${AUTH_DOMAIN}",
          "password": "${AUTH_ADMIN_PASS}"
        },
        "url": "ldaps://${AUTH_HOST}/",
        "directory_type": "ACTIVE_DIRECTORY",
        "domain_name": "${AUTH_DOMAIN}"
        "admin_user_reference_list": [],
        "admin_group_reference_list": [
          {
            "kind": "user_group",
            "name": "cn=ssp admins,cn=users,dc=ntnxlab,dc=local",
            "uuid": "45d495e1-b797-4a26-a45b-0ef589b42186"
          }
        ]
      }
    },
    "api_version": "3.1",
    "metadata": {
      "last_update_time": "2018-09-14T13:02:55Z",
      "kind": "directory_service",
      "uuid": "${_ldap_uuid}",
      "creation_time": "2018-09-14T13:02:55Z",
      "spec_version": 2,
      "owner_reference": {
        "kind": "user",
        "name": "admin",
        "uuid": "00000000-0000-0000-0000-000000000000"
      },
      "categories": {}
    }
  }
EOF
    )
    _ssp_connect=$(curl ${CURL_POST_OPTS} \
      --user ${PRISM_ADMIN}:${PE_PASSWORD} -X PUT --data "${_http_body}" \
      https://localhost:9440/api/nutanix/v3/directory_services/${_ldap_uuid})
    log "_ssp_connect=|${_ssp_connect}|"

}

###############################################################################################################################################################################
# Routine to enable Calm and proceed only if Calm is enabled
###############################################################################################################################################################################

function calm_enable() {
  local _http_body
  local _test
  local _sleep=30
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '

  log "Enable Nutanix Calm..."
  # Need to check if the PE to PC registration has been done before we move forward to enable Calm. If we've done that, move on.
  _json_data="{\"perform_validation_only\":true}"
  _response=($(curl $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d "${_json_data}" https://localhost:9440/api/nutanix/v3/services/nucalm | jq '.validation_result_list[].has_passed'))
  while [ ${#_response[@]} -lt 4 ]; do
    _response=($(curl $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d "${_json_data}" https://localhost:9440/api/nutanix/v3/services/nucalm | jq '.validation_result_list[].has_passed'))
    sleep 10
  done


  _http_body='{"enable_nutanix_apps":true,"state":"ENABLE"}'
  _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d "${_http_body}" https://localhost:9440/api/nutanix/v3/services/nucalm)

  # Sometimes the enabling of Calm is stuck due to an internal error. Need to retry then.
  _error_calm=$(echo $_test | grep "\"state\": \"ERROR\"" | wc -l)
  while [ $_error_calm -gt 0 ]; do
      _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d "${_http_body}" https://localhost:9440/api/nutanix/v3/services/nucalm)
      _error_calm=$(echo $_test | grep "\"state\": \"ERROR\"" | wc -l)
  done

  log "_test=|${_test}|"

  # Check if Calm is enabled
  while true; do
    # Get the progress of the task
    _progress=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} https://localhost:9440/api/nutanix/v3/services/nucalm/status | jq '.service_enablement_status' 2>nul | tr -d \")
    if [[ ${_progress} == "ENABLED" ]]; then
      log "Calm has been Enabled..."
      break;
    else
      log "Still enabling Calm.....Sleeping ${_sleep} seconds"
      sleep ${_sleep}
    fi
  done
}

###############################################################################################################################################################################
# Routine to make changes to the PC UI; Colors, naming and the Welcome Banner
###############################################################################################################################################################################

function pc_ui() {
  # http://vcdx56.com/2017/08/change-nutanix-prism-ui-login-screen/
  local  _http_body
  local       _json
  local _pc_version
  local       _test
#{"type":"WELCOME_BANNER","username":"system_data","key":"welcome_banner_content","value":"${PRISM_ADMIN}:${PE_PASSWORD}@${CLUSTER_NAME}"} \
  _json=$(cat <<EOF
{"type":"custom_login_screen","key":"color_in","value":"#ADD100"} \
{"type":"custom_login_screen","key":"color_out","value":"#11A3D7"} \
{"type":"custom_login_screen","key":"product_title","value":"${CLUSTER_NAME},PC-${PC_VERSION}"} \
{"type":"custom_login_screen","key":"title","value":"Nutanix.HandsOnWorkshops.com,@${AUTH_FQDN}"} \
{"type":"WELCOME_BANNER","username":"system_data","key":"welcome_banner_status","value":true} \
{"type":"WELCOME_BANNER","username":"system_data","key":"welcome_banner_content","value":"${PRISM_ADMIN}:${PE_PASSWORD}"} \
{"type":"WELCOME_BANNER","username":"system_data","key":"disable_video","value":true} \
{"type":"UI_CONFIG","username":"system_data","key":"disable_2048","value":true} \
{"type":"UI_CONFIG","key":"autoLogoutGlobal","value":7200000} \
{"type":"UI_CONFIG","key":"autoLogoutOverride","value":0} \
{"type":"UI_CONFIG","key":"welcome_banner","value":"https://Nutanix.HandsOnWorkshops.com/workshops/6070f10d-3aa0-4c7e-b727-dc554cbc2ddf/start/"}
EOF
  )

  for _http_body in ${_json}; do
    _test=$(curl ${CURL_HTTP_OPTS} \
      --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
      https://localhost:9440/PrismGateway/services/rest/v1/application/system_data)
    log "_test=|${_test}|${_http_body}"
  done

  _http_body='{"type":"UI_CONFIG","key":"autoLogoutTime","value": 3600000}'
       _test=$(curl ${CURL_HTTP_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/PrismGateway/services/rest/v1/application/user_data)
  log "autoLogoutTime _test=|${_test}|"

  # shellcheck disable=2206
  _pc_version=(${PC_VERSION//./ })

  if (( ${_pc_version[0]} >= 5 && ${_pc_version[1]} >= 10 && ${_test} != 500 )); then
    log "PC_VERSION ${PC_VERSION} >= 5.10, setting favorites..."

    _json=$(cat <<EOF
{"complete_query":"Karbon","route":"ebrowser/k8_cluster_entitys"} \
{"complete_query":"Images","route":"ebrowser/image_infos"} \
{"complete_query":"Projects","route":"ebrowser/projects"} \
{"complete_query":"Calm","route":"calm"}
EOF
    )

    for _http_body in ${_json}; do
      _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
        https://localhost:9440/api/nutanix/v3/search/favorites)
      log "favs _test=|${_test}|${_http_body}"
    done
  fi
}

###############################################################################################################################################################################
# Routine to Create a Project in the Calm part
###############################################################################################################################################################################

function pc_project() {
  local  _name
  local _count
  local  _uuid

   _name=${EMAIL%%@nutanix.com}.test
  _count=$(. /etc/profile.d/nutanix_env.sh \
    && nuclei project.list 2>/dev/null | grep ${_name} | wc --lines)
  if (( ${_count} > 0 )); then
    nuclei project.delete ${_name} confirm=false 2>/dev/null
  else
    log "Warning: _count=${_count}"
  fi

  log "Creating ${_name}..."
  nuclei project.create name=${_name} description='test from NuCLeI!' 2>/dev/null
  _uuid=$(. /etc/profile.d/nutanix_env.sh \
    && nuclei project.get ${_name} format=json 2>/dev/null \
    | jq .metadata.project_reference.uuid | tr -d '"')
  log "${_name}.uuid = ${_uuid}"

    # - project.get mark.lavi.test
    # - project.update mark.lavi.test
    #     spec.resources.account_reference_list.kind= or .uuid
    #     spec.resources.default_subnet_reference.kind=
    #     spec.resources.environment_reference_list.kind=
    #     spec.resources.external_user_group_reference_list.kind=
    #     spec.resources.subnet_reference_list.kind=
    #     spec.resources.user_reference_list.kind=

    # {"spec":{"access_control_policy_list":[],"project_detail":{"name":"mark.lavi.test1","resources":{"external_user_group_reference_list":[],"user_reference_list":[],"environment_reference_list":[],"account_reference_list":[],"subnet_reference_list":[{"kind":"subnet","name":"Primary","uuid":"a4000fcd-df41-42d7-9ffe-f1ab964b2796"},{"kind":"subnet","name":"Secondary","uuid":"4689bc7f-61dd-4527-bc7a-9d737ae61322"}],"default_subnet_reference":{"kind":"subnet","uuid":"a4000fcd-df41-42d7-9ffe-f1ab964b2796"}},"description":"test from NuCLeI!"},"user_list":[],"user_group_list":[]},"api_version":"3.1","metadata":{"creation_time":"2018-06-22T03:54:59Z","spec_version":0,"kind":"project","last_update_time":"2018-06-22T03:55:00Z","uuid":"1be7f66a-5006-4061-b9d2-76caefedd298","categories":{},"owner_reference":{"kind":"user","name":"admin","uuid":"00000000-0000-0000-0000-000000000000"}}}
}
