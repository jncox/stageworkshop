#!/usr/bin/env bash

# shellcheck disable=SC2034
RELEASE='release.json'
PC_DEV_VERSION='5.16'
PC_CURRENT_VERSION='5.11.2'
PC_STABLE_VERSION='5.11'
FILES_VERSION='3.6.0'
FILE_ANALYTICS_VERSION='2.0.1'
NTNX_INIT_PASSWORD='nutanix/4u'
PRISM_ADMIN='admin'
SSH_PUBKEY="${HOME}/.ssh/id_rsa.pub"
STORAGE_POOL='SP01'
STORAGE_DEFAULT='Default'
STORAGE_IMAGES='Images'
ATTEMPTS=40
SLEEP=60
ERA_Blueprint='EraServerDeployment.json'
Citrix_Blueprint=''

# Curl and SSH settings
CURL_OPTS='--insecure --silent --show-error' # --verbose'
CURL_POST_OPTS="${CURL_OPTS} --max-time 5 --header Content-Type:application/json --header Accept:application/json --output /dev/null"
CURL_HTTP_OPTS="${CURL_POST_OPTS} --write-out %{http_code}"
SSH_OPTS='-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null'
SSH_OPTS+=' -q' # -v'

##################################
#
# Look for JQ, AutoDC, and QCOW2 Repos in DC specific below.
#
##################################

QCOW2_IMAGES=(\
   CentOS7.qcow2 \
   Windows2016.qcow2 \
   Windows2012R2.qcow2 \
   Windows10-1709.qcow2 \
   ToolsVM.qcow2 \
   Linux_ToolsVM.qcow2 \
   ERA-Server-build-1.1.1.3.qcow2 \
   MSSQL-2016-VM.qcow2 \
   hycu-3.5.0-6253.qcow2 \
   VeeamAvailability_1.0.457.vmdk \
   move3.2.0.qcow2 \
   AutoXD.qcow2 \
)
ISO_IMAGES=(\
   CentOS7.iso \
   Windows2016.iso \
   Windows2012R2.iso \
   Windows10.iso \
   Nutanix-VirtIO-1.1.5.iso \
   SQLServer2014SP3.iso \
   XenApp_and_XenDesktop_7_18.iso \
   VeeamBR_9.5.4.2615.Update4.iso \
)

# shellcheck disable=2206
OCTET=(${PE_HOST//./ }) # zero index
IPV4_PREFIX=${OCTET[0]}.${OCTET[1]}.${OCTET[2]}
DATA_SERVICE_IP=${IPV4_PREFIX}.$((${OCTET[3]} + 1))
PC_HOST=${IPV4_PREFIX}.$((${OCTET[3]} + 2))
ERA_HOST=${IPV4_PREFIX}.$((${OCTET[3]} - 15))
CITRIX_DDC_HOST=${IPV4_PREFIX}.$((${OCTET[3]} + 8))
DNS_SERVERS='8.8.8.8'
NTP_SERVERS='0.us.pool.ntp.org,1.us.pool.ntp.org,2.us.pool.ntp.org,3.us.pool.ntp.org'
SUBNET_MASK="255.255.255.128"


NW1_NAME='Primary'
NW1_VLAN=0
NW1_SUBNET="${IPV4_PREFIX}.1/25"
NW1_GATEWAY="${IPV4_PREFIX}.1"
NW1_DHCP_START="${IPV4_PREFIX}.50"
NW1_DHCP_END="${IPV4_PREFIX}.125"

NW2_NAME='Secondary'
NW2_VLAN=$((OCTET[2]*10+1))
NW2_SUBNET="${IPV4_PREFIX}.129/25"
NW2_DHCP_START="${IPV4_PREFIX}.132"
NW2_DHCP_END="${IPV4_PREFIX}.253"

# Stuff needed for object_store
VLAN=${OCTET[2]}
NETWORK="${OCTET[0]}.${OCTET[1]}"

SMTP_SERVER_ADDRESS='mxb-002c1b01.gslb.pphosted.com'
SMTP_SERVER_FROM='NutanixHostedPOC@nutanix.com'
SMTP_SERVER_PORT=25

AUTH_SERVER='AutoDC' # default; TODO:180 refactor AUTH_SERVER choice to input file
AUTH_HOST="${IPV4_PREFIX}.$((${OCTET[3]} + 4))"
LDAP_PORT=389
AUTH_FQDN='ntnxlab.local'
AUTH_DOMAIN='NTNXLAB'
AUTH_ADMIN_USER='administrator@'${AUTH_FQDN}
AUTH_ADMIN_PASS='nutanix/4u'
AUTH_ADMIN_GROUP='SSP Admins'


# For Nutanix HPOC/Marketing clusters (RTP 10.55, PHC 10.42, PHX 10.38)
# https://sewiki.nutanix.com/index.php/HPOC_IP_Schema
case "${OCTET[0]}.${OCTET[1]}" in

  10.55 ) # HPOC us-east = DUR
    PC_DEV_METAURL='http://10.55.251.38/workshop_staging/euphrates-5.16-stable-prism_central-metadata.json'
    PC_DEV_URL='http://10.55.251.38/workshop_staging/euphrates-5.16-stable-prism_central.tar'
    PC_CURRENT_METAURL='http://10.55.251.38/workshop_staging/pcdeploy-5.11.2.json'
    PC_CURRENT_URL='http://10.55.251.38/workshop_staging/euphrates-5.11.2-stable-prism_central.tar'
    PC_STABLE_METAURL='http://10.55.251.38/workshop_staging/euphrates-5.11-stable-prism_central-metadata.json'
    PC_STABLE_URL='http://10.55.251.38/workshop_staging/euphrates-5.11-stable-prism_central.tar'
    FILES_METAURL='http://10.55.251.38/workshop_staging/afs-3.6.0.json'
    FILES_URL='http://10.55.251.38/workshop_staging/nutanix-afs-el7.3-release-afs-3.6.0-stable.qcow2'
    FILE_ANALYTICS_METAURL='http://10.55.251.38/workshop_staging/nutanix-file_analytics-el7.6-release-2.0.1-metadata.json'
    FILE_ANALYTICS_URL='http://10.55.251.38/workshop_staging/nutanix-file_analytics-el7.6-release-2.0.1.qcow2'
    JQ_REPOS=(\
         'http://10.55.251.38/workshop_staging/jq-linux64.dms' \
         'https://s3.amazonaws.com/get-ahv-images/jq-linux64.dms' \
         #'https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64' \
   )
    SSHPASS_REPOS=(\
       'http://10.55.251.38/workshop_staging/sshpass-1.06-2.el7.x86_64.rpm' \
       #'http://mirror.centos.org/centos/7/extras/x86_64/Packages/sshpass-1.06-2.el7.x86_64.rpm' \
    )
    QCOW2_REPOS=(\
       'http://10.55.251.38/workshop_staging/' \
       'https://s3.amazonaws.com/get-ahv-images/' \
    )
    AUTODC_REPOS=(\
     'http://10.55.251.38/workshop_staging/AutoDC2.qcow2' \
     'https://s3.amazonaws.com/get-ahv-images/AutoDC2.qcow2' \
   )
    PC_DATA='http://10.55.251.38/workshop_staging/seedPC.zip'
    BLUEPRINT_URL='http://10.55.251.38/workshop_staging/CalmBlueprints/'
    DNS_SERVERS='10.55.251.10,10.55.251.11'
    ;;
  10.42 ) # HPOC us-west = PHX
    PC_DEV_METAURL='http://10.42.194.11/workshop_staging/euphrates-5.16-stable-prism_central-metadata.json'
    PC_DEV_URL='http://10.42.194.11/workshop_staging/euphrates-5.16-stable-prism_central.tar'
    PC_CURRENT_METAURL='http://10.42.194.11/workshop_staging/pcdeploy-5.11.2.json'
    PC_CURRENT_URL='http://10.42.194.11/workshop_staging/euphrates-5.11.2-stable-prism_central.tar'
    PC_STABLE_METAURL='http://10.42.194.11/workshop_staging/euphrates-5.11-stable-prism_central-metadata.json'
    PC_STABLE_URL='http://10.42.194.11/workshop_staging/euphrates-5.11-stable-prism_central.tar'
    FILES_METAURL='http://10.42.194.11/workshop_staging/afs-3.6.0.json'
    FILES_URL='http://10.42.194.11/workshop_staging/nutanix-afs-el7.3-release-afs-3.6.0-stable.qcow2'
    FILE_ANALYTICS_METAURL='http://10.42.194.11/workshop_staging/nutanix-file_analytics-el7.6-release-2.0.1-metadata.json'
    FILE_ANALYTICS_URL='http://10.42.194.11/workshop_staging/nutanix-file_analytics-el7.6-release-2.0.1.qcow2'
    JQ_REPOS=(\
         'http://10.42.194.11/workshop_staging/jq-linux64.dms' \
         'https://s3.amazonaws.com/get-ahv-images/jq-linux64.dms' \
         #'https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64' \
   )
    SSHPASS_REPOS=(\
       'http://10.42.194.11/workshop_staging/sshpass-1.06-2.el7.x86_64.rpm' \
       #'http://mirror.centos.org/centos/7/extras/x86_64/Packages/sshpass-1.06-2.el7.x86_64.rpm' \
    )
    QCOW2_REPOS=(\
       'http://10.42.194.11/workshop_staging/' \
       'https://s3.amazonaws.com/get-ahv-images/' \
    )
    AUTODC_REPOS=(\
     'http://10.42.194.11/workshop_staging/AutoDC2.qcow2' \
     'https://s3.amazonaws.com/get-ahv-images/AutoDC2.qcow2' \
   )
    PC_DATA='http://10.42.194.11/workshop_staging/seedPC.zip'
    BLUEPRINT_URL='http://10.42.194.11/workshop_staging/CalmBlueprints/'
    DNS_SERVERS='10.42.196.10,10.42.194.10'
    ;;
  10.38 ) # HPOC us-west = PHX 1-Node Clusters
    PC_DEV_METAURL='http://10.42.194.11/workshop_staging/euphrates-5.16-stable-prism_central-metadata.json'
    PC_DEV_URL='http://10.42.194.11/workshop_staging/euphrates-5.16-stable-prism_central.tar'
    PC_CURRENT_METAURL='http://10.42.194.11/workshop_staging/pcdeploy-5.11.2.json'
    PC_CURRENT_URL='http://10.42.194.11/workshop_staging/euphrates-5.11.2-stable-prism_central.tar'
    PC_STABLE_METAURL='http://10.42.194.11/workshop_staging/euphrates-5.11-stable-prism_central-metadata.json'
    PC_STABLE_URL='http://10.42.194.11/workshop_staging/euphrates-5.11-stable-prism_central.tar'
    FILES_METAURL='http://10.42.194.11/workshop_staging/afs-3.6.0.json'
    FILES_URL='http://10.42.194.11/workshop_staging/nutanix-afs-el7.3-release-afs-3.6.0-stable.qcow2'
    FILE_ANALYTICS_METAURL='http://10.42.194.11/workshop_staging/nutanix-file_analytics-el7.6-release-2.0.1-metadata.json'
    FILE_ANALYTICS_URL='http://10.42.194.11/workshop_staging/nutanix-file_analytics-el7.6-release-2.0.1.qcow2'
    JQ_REPOS=(\
           'http://10.42.194.11/workshop_staging/jq-linux64.dms' \
           'https://s3.amazonaws.com/get-ahv-images/jq-linux64.dms' \
           #'https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64' \
     )
    SSHPASS_REPOS=(\
         'http://10.42.194.11/workshop_staging/sshpass-1.06-2.el7.x86_64.rpm' \
         #'http://mirror.centos.org/centos/7/extras/x86_64/Packages/sshpass-1.06-2.el7.x86_64.rpm' \
      )
    QCOW2_REPOS=(\
         'http://10.42.194.11/workshop_staging/' \
         'https://s3.amazonaws.com/get-ahv-images/' \
      )
    AUTODC_REPOS=(\
       'http://10.42.194.11/workshop_staging/AutoDC2.qcow2' \
       'https://s3.amazonaws.com/get-ahv-images/AutoDC2.qcow2' \
     )
    PC_DATA='http://10.42.194.11/workshop_staging/seedPC.zip'
    BLUEPRINT_URL='http://10.42.194.11/workshop_staging/CalmBlueprints/'
    DNS_SERVERS="10.42.196.10,10.42.194.10"
      ;;
  10.132 ) # https://sewiki.nutanix.com/index.php/SH-COLO-IP-ADDR
    JQ_REPOS=(\
         'https://s3.amazonaws.com/get-ahv-images/jq-linux64.dms' \
         #'https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64' \
   )
    QCOW2_REPOS=(\
       'https://s3.amazonaws.com/get-ahv-images/jq-linux64.dms' \
    )
    AUTODC_REPOS=(\
     'https://s3.amazonaws.com/get-ahv-images/AutoDC2.qcow2' \
   )

   DNS_SERVERS='10.132.71.40'
   NW1_SUBNET="${IPV4_PREFIX%.*}.128.4/17"
   NW1_DHCP_START="${IPV4_PREFIX}.100"
   NW1_DHCP_END="${IPV4_PREFIX}.250"
   # PC deploy file local override, TODO:30 make an PC_URL array and eliminate
   PC_CURRENT_URL=http://10.132.128.50/E%3A/share/Nutanix/PrismCentral/pc-${PC_VERSION}-deploy.tar
   PC_CURRENT_METAURL=http://10.132.128.50/E%3A/share/Nutanix/PrismCentral/pc-${PC_VERSION}-deploy-metadata.json
   PC_STABLE_METAURL=${PC_CURRENT_METAURL}

   QCOW2_IMAGES=(\
      Centos7-Base.qcow2 \
      Centos7-Update.qcow2 \
      Windows2012R2.qcow2 \
      panlm-img-52.qcow2 \
      kx_k8s_01.qcow2 \
      kx_k8s_02.qcow2 \
      kx_k8s_03.qcow2 \
    )
    ;;
esac

# Find operating system and set dependencies
if [[ -e /etc/lsb-release ]]; then
  # Linux Standards Base
  OS_NAME="$(grep DISTRIB_ID /etc/lsb-release | awk -F= '{print $2}')"
elif [[ -e /etc/os-release ]]; then
  # CPE = https://www.freedesktop.org/software/systemd/man/os-release.html
  OS_NAME="$(grep '^ID=' /etc/os-release | awk -F= '{print $2}')"
elif [[ $(uname -s) == 'Darwin' ]]; then
  OS_NAME='Darwin'
fi

WC_ARG='-l'
if [[ ${OS_NAME} == 'Darwin' ]]; then
  WC_ARG='-l'
fi
if [[ ${OS_NAME} == 'alpine' ]]; then
  WC_ARG='-l'
fi
