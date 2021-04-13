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
    38 {$nfs_host="10.42.194.11"}
    42 {$nfs_host="10.42.194.11"}
    55 {$nfs_host="10.55.251.38"}
}

# Set the username and password header
$Header_NTNX_Creds=@{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("admin:"+$password));}

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
# For this to work we need to connect from vCenter to ESXi and back
# ********************* vCenter level ***********************************************
# Connect to the vCenter of the environment
connect-viserver $VCENTER -User administrator@vsphere.local -Password $password | Out-Null

# Enable DRS on the vCenter
echo "Enabling DRS on the vCenter environment nd disabling Admission Control"
$cluster_name=(get-cluster| select $_.name).Name
Set-Cluster -Cluster $cluster_name -DRSEnabled:$true -HAAdmissionControlEnabled:$false -Confirm:$false | Out-Null

# Create a new Portgroup called Secondary with the correct VLAN
echo "Creating the Secondary network on the ESXi hosts"
$vmhosts = Get-Cluster $cluster_name | Get-VMhost
ForEach ($vmhost in $vmhosts){
    Get-VirtualSwitch -VMhost $vmhost -Name "vSwitch0" | New-VirtualPortGroup -Name Secondary -VlanId (($PE_IP.Split(".")[2] -as [int])*10+1) | Out-Null
}
echo "Uploading needed images"
# Create a ContentLibray and copy the needed images to it
New-ContentLibrary -Name "deploy" -Datastore "Images"
$images=@('esxi_ovas/AutoAD_Sysprep.ova','esxi_ovas/ERA-Server-build-2.1.1.1.ova','Citrix_Virtual_Apps_and_Desktops_7_1912.iso','CentOS7.iso','Windows2016.iso')
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

# Deploy an AutoAD OVA. DRS will take care of the rest.
$ESXi_Host=$vmhosts[0]
echo "Creating AutoAD VM via a Content Library in the Image Datastore"
Get-ContentLibraryitem -name 'AutoAD_Sysprep' | new-vm -Name AutoAD -vmhost $ESXi_Host -Datastore "vmContainer1" | Out-Null
# Set the network to VM-Network before starting the VM
get-vm 'AutoAD' | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName 'VM Network' -Confirm:$false | Out-Null

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

# Close the VMware connection
disconnect-viserver * -Confirm:$false

# ********************* PE level ***********************************************
# Confiure PE to use AutoAD for authentication and DNS server
echo "--------------------------------------"
echo "Switching to Nutanix environment"
$directory_url="ldap://"+$AutoAD+":389"
$error=45
  
echo "--------------------------------------"
echo "Adding "+$AutoAD+" as the Directory Server"

$Payload=@"
{
"connection_type": "LDAP",
"directory_type": "ACTIVE_DIRECTORY",
"directory_url": $directory_url,
"domain": "ntnxlab.local",
"group_search_type": "RECURSIVE",
"name": "ntnxlab.local",
"service_account_password": "administrator",
"service_account_username": "nutanix/4u"
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
echo "Adding SSP Admins AD Group to Cluster Admin Role"

$Payload=@"
{
    "directoryName": "ntnxlab.local",
    "role": "ROLE_CLUSTER_ADMIN",
    "entityType": "GROUP",
    "entityValues":[
        "SSP Admins"
    ]
}
"@

$APIParams = @{
    method="POST"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v1/authconfig/directories/ntnxlab.local/role_mappings?&entityType=GROUP&role=ROLE_CLUSTER_ADMIN"
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
echo "Add AutoAD to the DNS server confguration"

$APIParams = @{
    method="GET"
    Uri="https://"+$PE_IP+":9440/PrismGateway/services/rest/v2.0/cluster/name_servers"
    ContentType="application/json"
    Body=$Payload
    Header = $Header_NTNX_Creds
  }
  $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
  echo $response

# **********************************************************************************
# Deploy Prism Central
# **********************************************************************************
echo "Deploying the Prism Central to the environment"
echo "--------------------------------------"



# **********************************************************************************
# Reset Prism Central password to the same as PE
# **********************************************************************************


# **********************************************************************************
# Accept the PC Eula
# **********************************************************************************


# **********************************************************************************
# Disable PC pulse
# **********************************************************************************


# **********************************************************************************
# Enable Calm
# **********************************************************************************


# **********************************************************************************
# Enable Objects
# **********************************************************************************


# **********************************************************************************
# Enable Leap
# **********************************************************************************


# **********************************************************************************
# Run LCM
# **********************************************************************************



# **********************************************************************************
# Deploy blueperint where we set the DHCP server
# **********************************************************************************
