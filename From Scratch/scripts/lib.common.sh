#!/bin/bash
###################################################################################
# Commonly used function in the staging script
###################################################################################

function pause(){
	read -p "Press [Enter] key to proceed..."
}

function eula_pulse(){
	#####################################################################################
	# Accept the EULA and disable pulse
	#####################################################################################
	
	curl ${CURL_HTTP_OPTS} --user ${PRISM_USER}:${PE_PASSWORD} -X POST --data '{
	      "username": "SE Nutanix",
	      "companyName": "Nutanix",
	      "jobTitle": "SE"
	    }' https://${CLUSTER_VIP}:9440/PrismGateway/services/rest/v1/eulas/accept
	echo "Accepted the Eula..."

	curl ${CURL_HTTP_OPTS} --user ${PRISM_USER}:${PE_PASSWORD} -X PUT --data '{
	     "defaultNutanixEmail": null,
	     "emailContactList": null,
	     "enable": false,
	     "enableDefaultNutanixEmail": false,
	     "isPulsePromptNeeded": false,
	     "nosVersion": null,
	     "remindLater": null,
	     "verbosityType": null
	   }' https://${CLUSTER_VIP}:9440/PrismGateway/services/rest/v1/pulse
	echo "Diabled Pulse..."
}