# Set some environmental variables
Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -DefaultVIServerMode:Multiple -confirm:$false | Out-Null
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP:$false -confirm:$false | Out-Null


# **********************************************************************************
# Setting the needed variables
# **********************************************************************************
$parameters=get-content "./environment.env"
$password=$parameters.Split(",")[0]
$PE_IP=$parameters.Split(",")[1]

$AutoAD=$PE_IP.Substring(0,$PE_IP.Length-2)+"41"
$VCENTER=$PE_IP.Substring(0,$PE_IP.Length-2)+"40"
$PC_IP=$PE_IP.Substring(0,$PE_IP.Length-2)+"39"
$Era_IP=$PE_IP.Substring(0,$PE_IP.Length-2)+"43"
$GW=$PE_IP.Substring(0,$PE_IP.Length-2)+"1"

# Use the right NFS Host using the 2nd Octet of the PE IP address
switch ($PE_IP.Split(".")[1]){
    38 {
        $nfs_host="10.42.194.11"
        $vlan=(($PE_IP.Split(".")[2] -as [int])*10+3)
    }
    42 {
        $nfs_host="10.42.194.11"
        $vlan=(($PE_IP.Split(".")[2] -as [int])*10+1)
    }
    55 {
        $nfs_host="10.55.251.38"
        $vlan=(($PE_IP.Split(".")[2] -as [int])*10+1)
    }
}

# Set the username and password header
$Header_NTNX_Creds=@{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("admin:"+$password));}
$Header_NTNX_PC_temp_creds=@{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("admin:Nutanix/4u"));}

# **********************************************************************************
# ************************* Start of the script ************************************
# **********************************************************************************

# Get something on the screen...

echo "##################################################"
echo "Let's get moving"
echo "##################################################"

# **********************************************************************************
# PE Part of the script
# **********************************************************************************

# Accept the EULA

$APIParams = @{
    method="POST"
    Body='{"username":"NTNX","companyName":"NTNX","jobTitle":"NTNX"}'
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/eulas/accept"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
if ($response = "True"){
    echo "Eula Accepted"
}else{
    echo "Eula NOT accepted"
}

echo "--------------------------------------"

# Disable Pulse

$APIParams = @{
    method="PUT"
    Body='{"enable":"false","enableDefaultNutanixEmail":"false","isPulsePromptNeeded":"false"}'
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/pulse"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
if ($response = "True"){
    echo "Pulse Disabled"
}else{
    echo "Pulse NOT disabled"
}

echo "--------------------------------------"

# Change the name of the Storage Pool to SP1

# First get the Disk IDs

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/storage_pools?sortOrder=storage_pool_name"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck | ConvertTo-JSON -Depth 10)
$disks=($response | ConvertFrom-JSON).entities.disks | ConvertTo-JSON
$sp_id=($response | ConvertFrom-JSON).entities.id | ConvertTo-JSON

# Change the name of the Storage Pool

$Body=@"
{
    "id":$sp_id,
    "name":"SP01",
    "disks":$disks
}
"@
$APIParams = @{
    method="PUT"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/storage_pools?sortOrder=storage_pool_name"
    ContentType="application/json"
    Body=$Body
    Header = $Header_NTNX_Creds
}

$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
if ($response="True"){
    echo "Storage Pool has been renamed"
}else{
    echo "Storage Pool has not been renamed"
}

echo "--------------------------------------"

# Change the name of the defaulxxxx storage container to Default

# Get the ID and UUID of the default container first

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/storage_containers"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities | where-object {$_.name -match "efault"}
$default_cntr_id=$response.id | ConvertTO-JSON
$default_cntr_uuid=$response.storage_container_uuid | ConvertTO-JSON


$Payload=@"
{
    "id":$default_cntr_id,
    "storage_container_uuid":$default_cntr_uuid,
    "name":"default",
    "vstore_name_list":[
        "default"
    ]
}
"@

$APIParams = @{
    method="PATCH"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/storage_containers"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
if ($response = "True"){
    echo "Default Storage Container has been updated"
}else{
    echo "Default Storage Container has NOT been updated"
}

echo "--------------------------------------"

# Create the Images datastore

$Payload=@"
{
    "name": "Images",
    "marked_for_removal": false,
    "replication_factor": 2,
    "oplog_replication_factor": 2,
    "nfs_whitelist": [],
    "nfs_whitelist_inherited": true,
    "erasure_code": "off",
    "prefer_higher_ecfault_domain": null,
    "erasure_code_delay_secs": null,
    "finger_print_on_write": "off",
    "on_disk_dedup": "OFF",
    "compression_enabled": false,
    "compression_delay_in_secs": null,
    "is_nutanix_managed": null,
    "enable_software_encryption": false,
    "encrypted": null
}
"@

$APIParams = @{
  method="POST"
  Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/storage_containers"
  ContentType="application/json"
  Body=$Payload
  Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
if ($response = "True"){
    echo "Images Storage Container has been created"
}else{
    echo "Images Storage Container has NOT been created"
}

echo "--------------------------------------"

# Mount the Images container to all ESXi hosts

# Get the ESXi Hosts UUIDS

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/hosts/"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities.service_vmid
$host_ids=$response | ConvertTO-JSON

# Mount to all ESXi Hosts

$Payload=@"
{
    "containerName":"Images",
    "datastoreName":"",
    "nodeIds":$host_ids,
    "readOnly":false
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/containers/datastores/add_datastore"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
echo $response

echo "--------------------------------------"
echo "Concentrating on VMware environment.."

# **********************************************************************************
# Start the VMware environment manipulations
# **********************************************************************************

# Connect to the vCenter of the environment

connect-viserver $VCENTER -User administrator@vsphere.local -Password $password | Out-Null

# Enable DRS on the vCenter

echo "Enabling DRS on the vCenter environment and disabling Admission Control"
$cluster_name=(get-cluster| select $_.name).Name
Set-Cluster -Cluster $cluster_name -DRSEnabled:$true -HAAdmissionControlEnabled:$false -Confirm:$false | Out-Null

echo "--------------------------------------"

# Create a new Portgroup called Secondary with the correct VLAN

echo "Creating the Secondary network on the ESXi hosts"
$vmhosts = Get-Cluster $cluster_name | Get-VMhost

ForEach ($vmhost in $vmhosts){
    Get-VirtualSwitch -VMhost $vmhost -Name "vSwitch0" | New-VirtualPortGroup -Name Secondary -VlanId $vlan | Out-Null
}

echo "--------------------------------------"

echo "Uploading needed images"

# Create a ContentLibray and copy the needed images to it

New-ContentLibrary -Name "deploy" -Datastore "Images"
$images=@('esxi_ovas/AutoAD_Sysprep.ova','esxi_ovas/WinTools-AHV.ova','esxi_ovas/CentOS.ova','CentOS7.iso','Windows2016.iso')
foreach($image in $images){
    # Making sure we set the correct nameing for the ContentLibaray by removing the leading sublocation on the HTTP server
    if ($image -Match "/"){
        $image_name=$image.SubString(10)
    }else{
        $image_name=$image
    }
    # Remove the ova from the "templates" and the location where we got the Image from, but leave the isos alone
    if ($image -Match ".ova"){
        $image_short=$image.Substring(0,$image.Length-4)
        $image_short=$image_short.SubString(10)
    }else{
        $image_short=$image
    }
    get-ContentLibrary -Name 'deploy' -Local |New-ContentLibraryItem -name $image_short -FileName $image_name -Uri "http://$nfs_host/workshop_staging/$image"
    echo "Uploaded $image as $image_short in the deploy ContentLibrary"
}

echo "--------------------------------------"

# Deploy an AutoAD OVA. DRS will take care of the rest.

$ESXi_Host=$vmhosts[0]
echo "Creating AutoAD VM via a Content Library in the Image Datastore"
Get-ContentLibraryitem -name 'AutoAD_Sysprep' | new-vm -Name AutoAD -vmhost $ESXi_Host -Datastore "vmContainer1" | Out-Null

# Set the network to VM-Network before starting the VM

get-vm 'AutoAD' | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName 'VM Network' -Confirm:$false | Out-Null

echo "--------------------------------------"

echo "AutoAD VM has been created. Starting..."
Start-VM -VM 'AutoAD' | Out-Null

echo "Waiting till AutoAD is ready.."
$counter=1
$url="http://"+$AutoAD+":8000"
while ($true){
    try{
        $response=invoke-Webrequest -Uri $url -TimeOut 15
        Break
    }catch{
        echo "AutoAD still not ready. Sleeping 60 seconds before retrying...($counter/20)"
        sleep 60
        if ($counter -eq 20){
            echo "We waited for 20 minutes and the AutoAD didn't got ready in time..."
            exit 1
        }
        $counter++
    }
}
echo "AutoAD is ready for being used. Progressing..."
echo "--------------------------------------"

# Close the VMware connection

disconnect-viserver * -Confirm:$false

# **********************************************************************************
# Start the PE environment manipulations
# **********************************************************************************


# Confiure PE to use AutoAD for authentication and DNS server

$directory_url="ldap://"+$AutoAD+":389"
  
echo "Adding $AutoAD as the Directory Server"

$Payload=@"
{
"connection_type": "LDAP",
"directory_type": "ACTIVE_DIRECTORY",
"directory_url": "$directory_url",
"domain": "ntnxlab.local",
"group_search_type": "RECURSIVE",
"name": "NTNXLAB",
"service_account_username": "administrator@ntnxlab.local",
"service_account_password": "nutanix/4u"
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PE_IP+":9440/api/nutanix/v2.0/authconfig/directories/"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
  }
  $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
  if ($response = "True"){
      echo "Authorization to use NTNXLab.local has been created"
  }else{
      echo "Authorization to use NTNXLab.local has NOT been created"
  }

echo "--------------------------------------"

# Removing the DNS servers from the PE and add Just the AutoAD as its DNS server

echo "Updating DNS Servers"

# Fill the array with the DNS servers that are there

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/cluster/name_servers"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
$servers=$response

# Delete the DNS servers so we can add just one

foreach($server in $servers){
    $Payload='[{"ipv4":"'+$server+'"}]'
    echo $Payload
    $APIParams = @{
        method="POST"
        Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/cluster/name_servers/remove_list"
        ContentType="application/json"
        Body=$Payload
        Header = $Header_NTNX_Creds
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
}

# Get the AutoAD as correct DNS in

$Payload='{"value":"'+$AutoAD+'"}'
echo $Payload
$APIParams = @{
    method="POST"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/cluster/name_servers"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

echo "DNS Servers Updated"

cho "--------------------------------------"

echo "Adding SSP Admins AD Group to Cluster Admin Role"

$Payload=@"
{
    "directoryName": "NTNXLAB",
    "role": "ROLE_CLUSTER_ADMIN",
    "entityType": "GROUP",
    "entityValues":[
        "SSP Admins"
    ]
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/authconfig/directories/NTNXLAB/role_mappings?&entityType=GROUP&role=ROLE_CLUSTER_ADMIN"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
  }
  $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
  if ($response = "True"){
      echo "SSP Admins have been added as the Cluster Admin Role"
  }else{
      echo "SSP Admins have not been added as the CLuster Admin Role"
  }

echo "--------------------------------------"


# Deploy Prism Central

echo "Deploying the Prism Central to the environment"

# Get the Storage UUID as we need it before we can deploy PC

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/storage_containers"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities | where-object {$_.name -match "vmContainer1"}
$cntr_uuid=$response.storage_container_uuid


# Get the Network UUID as we need it before we can deploy PC

$APIParams = @{
  method="GET"
  Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/networks"
  ContentType="application/json"
  Body=$Payload
  Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).entities | where-object {$_.name -match "VM Network"}
$network_uuid=$response.uuid


$Payload=@"
{
    "resources":{
        "version":"pc.2021.1.0.1",
        "should_auto_register":true,
        "pc_vm_list":[
            {
                "vm_name":"pc-2021.1",
                "container_uuid":"$cntr_uuid",
                "num_sockets":6,
                "data_disk_size_bytes":536870912000,
                "memory_size_bytes":27917287424,
                "dns_server_ip_list":[
                    "$AutoAD"
                ],
                "nic_list":[
                    {
                        "ip_list":[
                            "$PC_IP"
                        ],
                        "network_configuration":{
                            "network_uuid":"$network_uuid",
                            "subnet_mask":"255.255.255.128",
                            "default_gateway":"$GW"
                        }
                    }
                ]
            }
        ]
    }
}
"@

$APIParams = @{
  method="POST"
  Uri="https://"+$PE_IP+":9440/api/nutanix/v3/prism_central"
  ContentType="application/json"
  Body=$Payload
  Header = $Header_NTNX_Creds
}
try{
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
}catch{
    echo "The PC download and deployment could not be executed. Exiting the script."
    echo "Received error was: $_.Exception.Message"
    exit 1
}


echo "Deployment of PC has started. Now need to wait till it is up and running"
echo "Waiting till PC is ready.. (could take up to 30+ minutes)"
$counter=1
$url="https://"+$PC_IP+":9440"

# Need temporary default credentials

$username = "admin"
$password_default = "Nutanix/4u" | ConvertTo-SecureString -asPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($username,$password_default)
while ($true){
    try{
        $response=invoke-Webrequest -Uri $url -TimeOut 15 -SkipCertificateCheck -Credential $cred
        Break
    }catch{
        echo "PC still not ready. Sleeping 60 seconds before retrying...($counter/45)"
        sleep 60
        if ($counter -eq 45){
            echo "We waited for 45 minutes and the AutoAD didn't got ready in time..."
            exit 1
        }
        $counter++
    }
}
echo "PC is ready for being used. Progressing..."
echo "--------------------------------------"

# Check if registration was successfull of PE to PC

echo "Checking if PE has been registred to PC"
$APIParams = @{
  method="GET"
  Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/multicluster/cluster_external_state"
  ContentType="application/json"
  Body=$Payload
  Header = $Header_NTNX_Creds
}
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
$count=1
while ($response.clusterDetails.ipAddresses -eq $null){
    echo "PE is not yet registered to PC. Waiting a bit more.."
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    sleep 60
    if ($count -gt 10){
        echo "Waited for 10 minutes. Giving up. Exiting the script."
        exit 3
    }
    $count++
}
echo "PE has been registered to PC. Progressing..."
echo "--------------------------------------"

# **********************************************************************************
# Start the PC environment manipulations
# **********************************************************************************


# Set Prism Central password to the same as PE

$Payload='{"oldPassword":"Nutanix/4u","newPassword":"'+$password+'"}'
$APIParams = @{
    method="POST"
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/utils/change_default_system_password"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_PC_temp_creds
}

# Need to use the Default creds to get in and set the password, only once

$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck -Credential $cred)
if ($response = "True"){
    echo "PC Password has been changed to the same as PE"
}else{
    echo "PC Password has NOT been changed to the same as PE. Exiting script."
    exit 2
}

echo "--------------------------------------"


# Accept the PC Eula

$APIParams = @{
    method="POST"
    Body='{"username":"NTNX","companyName":"NTNX","jobTitle":"NTNX"}'
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/eulas/accept"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
if ($response = "True"){
    echo "Eula Accepted"
}else{
    echo "Eula NOT accepted"
}

echo "--------------------------------------"


# Disable PC pulse

$APIParams = @{
    method="PUT"
    Body='{"enable":"false","enableDefaultNutanixEmail":"false","isPulsePromptNeeded":"false"}'
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/pulse"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
if ($response = "True"){
    echo "Pulse Disabled"
}else{
    echo "Pulse NOT disabled"
}

echo "--------------------------------------"

# Add the AutoAD as the Directory server

$directory_url="ldap://"+$AutoAD+":389"

  
echo "Adding $AutoAD as the Directory Server"

$Payload=@"
{
"connection_type": "LDAP",
"directory_type": "ACTIVE_DIRECTORY",
"directory_url": "$directory_url",
"domain": "ntnxlab.local",
"group_search_type": "RECURSIVE",
"name": "NTNXLAB",
"service_account_username": "administrator@ntnxlab.local",
"service_account_password": "nutanix/4u"
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PC_IP+":9440/api/nutanix/v2.0/authconfig/directories/"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
  }
  $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
  if ($response = "True"){
      echo "Authorization to use NTNXLab.local has been created"
  }else{
      echo "Authorization to use NTNXLab.local has NOT been created"
  }

echo "--------------------------------------"

# Add the Role to the SSP Admins group

echo "Adding SSP Admins AD Group to Cluster Admin Role"

$Payload=@"
{
    "directoryName": "NTNXLAB",
    "role": "ROLE_CLUSTER_ADMIN",
    "entityType": "GROUP",
    "entityValues":[
        "SSP Admins"
    ]
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/authconfig/directories/NTNXLAB/role_mappings?&entityType=GROUP&role=ROLE_CLUSTER_ADMIN"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
  }
  $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
  if ($response = "True"){
      echo "Authorization to use NTNXLab.local has been created"
  }else{
      echo "Authorization to use NTNXLab.local has NOT been created"
  }


echo "Role Added"
echo "--------------------------------------"


# **********************************************************************************
# Enable Calm
# **********************************************************************************
echo "Enabling Calm"


# Need to check if the PE to PC registration has been done before we move forward to enable Calm. If we've done that, move on.

$APIParams = @{
    method="POST"
    Body='{"perform_validation_only":true}'
    Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/nucalm"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).validation_result_list.has_passed
while ($response.length -lt 5){
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).validation_result_list.has_passed
}

# Enable Calm

$APIParams = @{
    method="POST"
    Body='{"enable_nutanix_apps":true,"state":"ENABLE"}'
    Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/nucalm"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).state

# Sometimes the enabling of Calm is stuck due to an internal error. Need to retry then.

while ($response -Match "ERROR"){
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).state
}

# Check if Calm is enabled

$APIParams = @{
    method="GET"
    Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/nucalm/status"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_enablement_status
while ($response -NotMatch "ENABLED"){
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_enablement_status
}
echo "Calm has been enabled"
echo "--------------------------------------"

# **********************************************************************************
# Enable Objects
# **********************************************************************************
echo "Enabling Objects"

# Enable Objects

$APIParams = @{
    method="POST"
    Body='{"state":"ENABLE"}'
    Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/oss"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

# Check if the Objects have been enabled

$APIParams = @{
    method="POST"
    Body='{"entity_type":"objectstore"}'
    Uri="https://"+$PC_IP+":9440/oss/api/nutanix/v3/groups"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).total_group_count

# Run a short waitloop before moving on

$counter=1
while ($response -lt 1){
    echo "Objects not yet ready to be used. Waiting 10 seconds before retry ($counter/30)"
    sleep 10
    if ($counter -eq 30){
        echo "We waited for five minutes and Objects didn't become enabled."
        break
    }
    $counter++
}
if ($counter -eq 30){
    echo "Objects has not been enabled. Please use the UI.."
}else{
    echo "Objects has been enabled"
}
echo "--------------------------------------"

# **********************************************************************************
# Enable Leap
# **********************************************************************************
echo "Checking if Leap can be enabled"

# Check if the Objects have been enabled

$APIParams = @{
    method="GET"
    Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/disaster_recovery/status?include_capabilities=true"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_capabilities.can_enable.state
if ($response -eq $true){
    echo "Leap can be enabled, so progressing."
    $APIParams = @{
        method="POST"
        Body='{"state":"ENABLE"}'
        Uri="https://"+$PC_IP+":9440/api/nutanix/v3/services/disaster_recovery"
        ContentType="application/json"
        Header = $Header_NTNX_Creds
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).task_uuid
    # We have been given a task uuid, so need to check if SUCCEEDED as status
    $APIParams = @{
        method="GET"
        Uri="https://"+$PC_IP+":9440/api/nutanix/v3/tasks/$response"
        ContentType="application/json"
        Header = $Header_NTNX_Creds
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
    # Loop for 2 minutes so we can check the task being run successfuly
    $counter=1
    while ($response -NotMatch "SUCCEEDED"){
        sleep 10
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
        if ($counter -eq 12){
            echo "Waited two minutes and Leap didn't get enabled! Please check the PC UI for the reason."
        }else{
            echo "Leap has been enabled"
        }
    }
    if ()
}else{
    echo "Leap can not be enabled! Please check the PC UI for the reason."
}
echo "--------------------------------------"

# **********************************************************************************
# Enable Karbon
# **********************************************************************************
echo "Enabling Karbon"

$Payload_en='{"value":"{\".oid\":\"ClusterManager\",\".method\":\"enable_service_with_prechecks\",\".kwargs\":{\"service_list_json\":\"{\\\"service_list\\\":[\\\"KarbonUIService\\\",\\\"KarbonCoreService\\\"]}\"}}"}'
$Payload_chk='{"value":"{\".oid\":\"ClusterManager\",\".method\":\"is_service_enabled\",\".kwargs\":{\"service_name\":\"KarbonUIService\"}}"}'

# Enable Karbon

$APIParams = @{
    method="POST"
    Body=$Payload_en
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/genesis"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
if ($response.value -Match "true"){
    echo "Enable Karbon command has been received. Waiting for karbon to be ready"
}else{
    echo "Retrying enablening Karbon one more time"
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    sleep 10
}

# Checking if Karbon has been enabled

$APIParams = @{
    method="POST"
    Body=$Payload_chk
    Uri="https://"+$PC_IP+":9440/PrismGateway/services/rest/v1/genesis"
    ContentType="application/json"
    Header = $Header_NTNX_Creds
} 
$response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
$counter=1
while ($response.value -NotMatch "true"){
    echo "Karbon is not ready"
    sleep 10
    if ($counter -eq 12){
        echo "We tried for 2 minutes and Karbon is still not enabled."
        break
    }
    $counter++
}
if ($counter -eq 12){
    echo "Please use the UI to enable Karbon"
}else{
    echo "Karbon has been enabled"
}

echo "--------------------------------------"

# **********************************************************************************
# Run LCM
# **********************************************************************************


# **********************************************************************************
# Deploy blueperint where we set the DHCP server
# **********************************************************************************
