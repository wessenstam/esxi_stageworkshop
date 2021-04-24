#!/bin/bash
###################################################################################
# Commonly used function in the staging script for VMware related stuff
###################################################################################

# -----------------------------------------------------------------------------------
# Check if we are running on a HPOC or a local installation.
# HPOC has VCSA vm already installed and is running in the vmContainer1
# If the environment this script is talking to is HPOC, we can skip a lot of work!!
# 1. vCenter will be at .40 address
# 2. It will have the provided password which is the same as the PE password
# 3. Username will be administrator@vsphere.local
# 4. We just need to test/check if we can get an authentication ID and skip to the next steps.
# -----------------------------------------------------------------------------------
function hpoc_check(){
	# Are we in HPOC? Checking by vmContainer1 exists
	_hpoc_env=$(curl -X POST $CURL_HTTP_OPTS --user $VCSA_USER:$VCSA_PWD https://${VCSA_IP}/rest/com/vmware/cis/session | jq '.value' | wc -l)
	if [ $_hpoc_env -eq 1 ]; then
		# Checking if the vCenter is responding at the .40 address
		return 0
	else
		return 1
	fi
}

###################################################################################
# Create a VMware_vcsa storage container for the VCSA in the Nutanix Solution
###################################################################################
function vcsa_storage(){

		# The first parameter is the name of the storage container to create. If it is empty this is for vmContainer1.
		if [ -z $1 ]; then
			datastoreName="vmContainer1"
		else
			datastoreName=$1
		fi

		# Does the VMware_vcsa storage container exists if no, create it....
		_exists=$(curl $CURL_HTTP_OPTS --user $PRISM_USER:$PE_PASSWORD https://${CLUSTER_VIP}:9440/PrismGateway/services/rest/v1/containers | jq '.entities[].name' | grep $datastoreName | wc -l)

		if [ $_exists -le 0 ]; then
			echo "Creating the $datastoreName storage container...."

			# run the curl command
			response=$(curl -X POST -d '{"advertised_capacity": 0,"max_capacity": 0,"name": "$datastoreName","vstore_name_list": ["$datastoreName"]}"' ${CURL_HTTP_OPTS} --user ${PRISM_USER}:${PE_PASSWORD} https://${CLUSTER_VIP}:9440/api/nutanix/v2.0/storage_containers/ | grep "true" | wc -l)

			# Has it been created?
			if [ $response -gt 0 ]; then
				echo "Storage Container has been created.."
			else
				echo "Storage container not created.. Exiting as this is an important dependency..."
				exit 1
			fi
		else
			echo "Storage container already exists... Moving on..."
		fi

		# Check if the $datastoreName is mounted on all nodes in the cluster
		# On how many nodes has the $datastoreName been mounted
		hosts_mounted=($(curl $CURL_HTTP_OPTS --user ${PRISM_USER}:${PE_PASSWORD} https://${CLUSTER_VIP}:9440/PrismGateway/services/rest/v1/containers/datastores | jq '.[] | select (.containerName=="$datastoreName") | .hostIpAddress' | tr -d \"))


		# How much nodes are there in the cluster?
		cluster_hosts_num=$(curl $CURL_HTTP_OPTS --user ${PRISM_USER}:${PE_PASSWORD} https://${CLUSTER_VIP}:9440/PrismGateway/services/rest/v2.0/cluster/ | jq '.num_nodes')

		# Are all nodes mounted then skipp below
		if [ ${hosts_mounted[@]} -ne $cluster_hosts_num ]; then

			# Get the UUIDs of the Hypervisor hosts so we can mount the just created container to all of them
			_connected_ar=($(curl $CURL_HTTP_OPTS --user ${PRISM_USER}:${PE_PASSWORD} https://${CLUSTER_VIP}:9440/PrismGateway/services/rest/v1/hosts | jq '.entities[].serviceVMId' | tr -d \\\"))

			# create the json_payload
			# Begin of the payload string
			_json_data="{\"containerName\":\"$datastoreName\",\"datastoreName\":\"\",\"nodeIds\":["

			# Loop throught the array so we get the full _json_data payload
			count=0
			while [ $count -lt ${#_connected_ar[@]} ]
			do
				_json_data+="\"${_connected_ar[$count]}\","
				let count=count+1
			done

			# Remove the last "," as we don't need it.
			_json_data=${_json_data%?};

			# Last part of the json payload
			_json_data+="],\"readOnly\":false}"

			# Add the newly created datastore to all ESXi Servers
			_connect_cntr=$(curl -X POST -d $_json_data $CURL_HTTP_OPTS --user ${PRISM_USER}:${PE_PASSWORD} https://${CLUSTER_VIP}:9440/PrismGateway/services/rest/v1/containers/datastores/add_datastore | grep "\"successful\":true" | wc -l)


			# Check the outcome of the command
			# !!!!!!!!!!!
			# TODO!!! NEED TO MAKE A LOOP OUT OF THIS AS THIS IS A BIG DEPENDENCIES THAT NEEDS TO BE SOLVED!!!!
			# !!!!!!!!!!!
			if [ ${_connect_cntr} -lt 1 ]; then
				echo "Container has not been mounted on all ESXi hosts..... Exiting as this is an important dependency!!"
				#exit 1
			else
				echo "Container has been mounted on all ESXi hosts..... Moving on..."
			fi
		fi
}



#####################################################################################
# Creating the VCSA installation part
#####################################################################################
function vcsa_install(){

	# Grabbing the information from the cluster as we need to have the IP address of one of the VMware hosts
	# Create the json Payload to grab the data of the "leading" hyper-visor
	_json_data="{\"kind\":\"cluster\",\"length\":500,\"offset\":0}"

	# get the IP address from the first hypervisor node
	hypervisor1_ip=$(curl -X POST -d ${_json_data} ${CURL_HTTP_OPTS} --user ${PRISM_USER}:${PE_PASSWORD} https://${CLUSTER_VIP}:9440/api/nutanix/v3/clusters/list | jq '.entities[0].status.resources.nodes.hypervisor_server_list[0].ip' | tr -d \")

	# Edit the json file that needs to be manipulated so we can run the installer of the VCSA
	# Used https://www.altaro.com/vmware/vcenter-server-appliance-6-5-u1-linux/

	# Grabbing the deploy-json template file from the defined image server
	curl $CURL_HTTP_OPTS http://$IMAGES_SERVER/workshop_staging/deploy-vcsa-templ.json -o /tmp/deploy-vcsa.json

	echo "Manipulating the VCSA deploy json file using the defined parameters...."
	# using sed to manipulate the json file
	# change the ESXi Host for deployment
	sed -i "s/\"ESXI_HOSTIP\"/\"${hypervisor1_ip}\"/g" /tmp/deploy-vcsa.json
	# change the root password for teh ESXi host
	sed -i "s/\"PASSWORD\"/\"${PE_PASSWORD}\"/g" /tmp/deploy-vcsa.json
	# Change the VCSA-IP, default at .50 of the same IP address range
	sed -i "s/\"VCSA_IP\"/\"${VCSA_IP}\"/g" /tmp/deploy-vcsa.json
	# Change the DNSSERVERS
	sed -i "s/\"DNSSERVERS\"/\"${DNSSERVERS}\"/g" /tmp/deploy-vcsa.json
	# Change the VCSA-GW
	sed -i "s/\"VCSA_GW\"/\"${VCSA_GW}\"/g" /tmp/deploy-vcsa.json
	# Change the OS_PASSWORD}
	sed -i "s/\"OS_PASSWORD\"/\"${PE_PASSWORD}\"/g" /tmp/deploy-vcsa.json
	# Change the SSO_PASSWORD
	sed -i "s/\"SSO_PASSWORD\"/\"${PE_PASSWORD}\"/g" /tmp/deploy-vcsa.json

	# Creating the mount to the NFS share
	echo "Mounting the VCSA Installation location to NDS"
	mkdir -p /media/nfs
	mount -t nfs $IMAGES_SERVER:/$IMAGES_LOCATION /media/nfs

	# Run the installer in the background
	# Manipulating the script so we can run the installer
	ROOT="${VCSA_INST_DIR}/vcsa-cli-installer/lin64"
	export LD_LIBRARY_PATH=$ROOT/openssl-1.0.2k/lib/:$ROOT/libffi-3.0.9/lib/
	#nohup
	exec "$ROOT/vcsa-deploy.bin" install --accept-eula --no-esx-ssl-verify /tmp/deploy-vcsa.json #> /tmp/vcenter$_counter.log 2>&1 </dev/null &
	#echo "started the vCenter installation in the background. Please run:"
	#echo "tail -f -n 50 ~/vcenter$_counter.log to see the progress..."
	#echo "--------------------------------------------------"

	# We will loop for a max of 20 minutes before we kill all
	_loop=0
	while :
	do
		last_line=$(cat ~/vcenter.log | grep "Finished successfully" | wc -l)
		if [ $last_line -gt 0 ]; then
			echo "vCenter has been installed..."
			break
	   elif [[ $_loop -gt 20 ]]; then
	   		echo "It has taken to long for vCenter to be installed (20+ minutes). As this is an important dependency we stop the script..."
	   		exit 1
	   	else
	       echo "vCenter is still being installed... Waiting 60 seconds. It may take up to 20 minutes before all is well...."
	       let _loop++
	       sleep 60
		fi
	done

}

#####################################################################################
# Register vCenter
#####################################################################################
function register_vcenter(){
	_json_data="{\"adminUsername\":\"administrator@vsphere.local\",\"adminPassword\":\"${PE_PASSWORD}\",\"ipAddress\":\"${VCSA_IP}\",\"port\":\"443\"}"
	_task_id=$(curl -X POST -d ${_json_data} ${CURL_HTTP_OPTS} --user ${PRISM_USER}:${PE_PASSWORD} https://${CLUSTER_VIP}:9440/PrismGateway/services/rest/v1/management_servers/register)
	if [ -z $_task_id ]; then
		echo "vCenter registration retry once..."
		_task_id=$(curl -X POST -d ${_json_data} ${CURL_HTTP_OPTS} --user ${PRISM_USER}:${PE_PASSWORD} https://${CLUSTER_VIP}:9440/PrismGateway/services/rest/v1/management_servers/register)
	elif
		echo "vCenter registration has started..."
		_status=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_USER}:${PE_PASSWORD} https://${CLUSTER_VIP}:9440/api/nutanix/v3/tasks/${_task_id} | jq '.status' | tr -d \" | grep -wci "SUCCEEDED")

		# loop registration; stop the script after 2 minutes as now it has failed probably...
		while [ $_status -lt 1 ]
		do
			_status=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_USER}:${PE_PASSWORD} https://${CLUSTER_VIP}:9440/api/nutanix/v3/tasks/${_task_id} | jq '.status' | tr -d \" | grep -wci "SUCCEEDED")
			if [ $_status -gt 0 ]; then
				echo "vCenter has been registered..."
				break
			elif [[ $_loop -gt 4 ]]; then
				echo "Registration has taken more then 2 minutes. Exiting script as this is an important dependency for the rest of the script..."
				exit 1
			else
				echo "vCenter registration is still running... Waiting 30 seconds. It may take up to 2 minutes before all is well...."
	       		let _loop++
	       		sleep 30
		done
	fi
}

#####################################################################################
# Create the network stuff
#####################################################################################
function upload_pc(){

}


#####################################################################################
# Create the authentication ID needed for the vCenter stuff stuff
#####################################################################################
function auth_vcenter(){
	auth_id=$(curl -X POST https://${VCSA_IP}/rest/com/vmware/cis/session --user ${VCSA_USER}:${VCSA_PASSWD} --insecure --silent | jq '.value' | tr -d \")
	if [ -z $auth_id ]; then
		echo "We have not received any value from the vCenter..."
		exit 1
	else
		set vc_auth_header="-H \"cookie: vmware-api-session-id=${auth_id}\""
	fi
}

#####################################################################################
# Create the network stuff
#####################################################################################


#####################################################################################
# CLEAN UP everything that we used to install the VMware stuff
#####################################################################################
function cleanup_vmware(){
	echo "Cleaning up the temporary used nfs mount and files"
	# unmount the iso and remove the created stuff
	umount /media/nfs
	rm -rf /media/nfs
	rm -rf /tmp/deploy*

}
