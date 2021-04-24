#!/bin/bash
#####################################################################################
# This file holds all the needed global variables that are used in the different scripts
#####################################################################################

# NUTANIX CLUSTER Realted variables
CLUSTER_INFO=$(cat cluster.txt | grep -v \#)
CLUSTER_INFO_AR=(${CLUSTER_INFO//|/ })
CLUSTER_VIP=${CLUSTER_INFO_AR[0]}
PE_PASSWORD=${CLUSTER_INFO_AR[1]}
PRISM_USER='admin'
EMAIL=${CLUSTER_INFO_AR[2]}
SSHPASS=${PRISM_USER}

OCTET=(${CLUSTER_VIP//./ })
IPV4_PREFIX=${OCTET[0]}.${OCTET[1]}.${OCTET[2]}
IPV4_SHORT=${OCTET[0]}.${OCTET[1]}
CURL_HTTP_OPTS=' --silent --max-time 25 --header Content-Type:application/json --header Accept:application/json  --insecure '
DNSSERVERS='8.8.8.8'

# NFS server loaction and share
# Depending on the location RTP (10.55) or PHX (10.42) we make changes to the IMAGESERVER variable
if [ ${OCTET[1]} -eq 55 ]; then
	IMAGES_SERVER="10.55.251.38"
else
	IMAGES_SERVER="10.42.194.11"
fi 
IMAGES_DATA=$(cat image_server.txt | grep -v \#)
IMAGES_DATA_AR=(${IMAGES_DATA//|/ })
IMAGES_LOCATION="images"
NFS_LOCATION="/media/nfs"

# VMware related Variables
VCSA_USER='administrator@vsphere.local'
VCSA_PWD=${PE_PASSWORD}
VCSA_GW=$IPV4_PREFIX."1"
VCSA_IP=$IPV4_PREFIX."40"
VCSA_INST_DIR="${NFS_LOCATION}/VMware/vSphere 6.5/VMware-VCSA-all-6.5.0-7119157"