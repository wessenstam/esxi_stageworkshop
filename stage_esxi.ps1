# Set some environmental variables
Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -confirm:$false | Out-Null
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP:$false -confirm:$false | Out-Null


# **********************************************************************************
# Setting the needed variables
# **********************************************************************************
$parameters=get-content ./environment.env
$password=$parameters.Split(",")[0]
$PE_IP=$parameters.Split(",")[1]

$AutoAD=$PE_IP.Substring(0,$PE_IP.Length-2)+"41"
$VCENTER=$PE_IP.Substring(0,$PE_IP.Length-2)+"40"
$PC_IP=$PE_IP.Substring(0,$PE_IP.Length-2)+"39"
$Era_IP=$PE_IP.Substring(0,$PE_IP.Length-2)+"43"
$GW=$PE_IP.Substring(0,$PE_IP.Length-2)+"1"

# Use the right NFS Host using the 2nd Octet of the PE IP address
switch ($PE_HOST.Split(".")[1]){
    38 {$nfs_host="10.42.194.11"}
    42 {$nfs_host="10.42.194.11"}
    55 {$nfs_host="10.55.251.38"}
}

# Set the username and password header
$Header_NTNX_Creds_NTNX_Creds=@{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("admin:"+$password));}

# **********************************************************************************
# ************************* Start of the script ************************************
# **********************************************************************************

# Get something on the screen...
echo "##################################################"
echo "Let's get moving"
echo "##################################################"

cd /script

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
    echo "Eula Excepted"
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


# **********************************************************************************
# Start the VMware environment manipulations
# **********************************************************************************
# For this to work we need to connect from vCenter to ESXi and back
# ********************* vCenter level ***********************************************
# Connect to the vCenter of the environment
connect-viserver $VCENTER -User administrator@vsphere.local -Password $password | Out-Null

# Enable DRS on the vCenter
$cluster_name=(get-cluster| select $_.name).Name
Set-Cluster -Cluster $cluster_name -DRSEnabled:$true | Out-Null

# Create a new Portgroup called Secondary with the correct VLAN
$vmhosts = Get-Cluster $cluster_name | Get-VMhost
ForEach ($vmhost in $vmhosts){
    Get-VirtualSwitch -VMhost $vmhost -Name $vSwitch | New-VirtualPortGroup -Name Secondary -VlanId (($PE_HOST.Split(".")[2] -as [int])*10+1) | Out-Null
}

# Disconnect from the vCenter
disconnect-viserver * -confirm:$false

# ************************** ESXi Host Level *****************************************
# Create a temp NFS Datastore for the ISO image copying via one of the ESXi_Hosts
$ESXi_Host=$vmhosts[0].name
connect-viserver $ESXi_Host -User root -Password $password -Confirm:$false | Out-Null
Get-VMHost $ESXi_Host | New-Datastore -Nfs -Name nfs_temp -Path /workshop_staging -NfsHost $nfs_host

# Make two new Datastore objects
$datastore1=Get-datastore -name "nfs01"
$datastore2=Get-datastore -name "Images"
New-PSDrive -Location $datastore1 -Name DS1 -PSProvider VimDatastore -Root "\" -Confirm:$false | Out-Null
New-PSDrive -Location $datastore2 -Name DS2 -PSProvider VimDatastore -Root "\" -Confirm:$false | Out-Null

# Copy the needed files to the Images Datastore
$files_arr=@('CentOS7.iso','Windows2016.iso','Nutanix-VirtIO-1.1.5.iso','Citrix_Virtual_Apps_and_Desktops_7_1912.iso',"AutoAD.vmdk")
foreach ($file in $files_arr){
    Copy-DatastoreItem -Item DS:\$file -Destination DS2:\ -Confirm:$false 
}

# Remove the two drives so the cleanup happens
Remove-PSDrive -Name DS1
Remove-PSDrive -Name DS2

# Remove the temp mounted Datastore
Remove-Datastore -Datastore nfs_temp -VMHost $ESXi_Host -Confirm:$false | Out-Null

# Disconnect from the ESXi Host
disconnect-viserver * -Confirm:$false | Out-Null

# ********************* vCenter level ***********************************************
# Connect to the vCenter of the environment
connect-viserver $VCENTER -User administrator@vsphere.local -Password $password | Out-Null

# Need to create a Customisation Profile or we can not set Static IP
New-OSCustomizationSpec -OrgName "TE" -OSType Windows -Name PowerCliOnly  -Workgroup "Deployment" -FullName "Administrator" -Confirm:$false
#Get-OSCustomizationNicMapping -OSCustomizationSpec PowerCliOnly | Set-OSCustomizationNicMapping -Position 1 -IpMode UseStaticIP -IpAddress $AutoAD -SubnetMask 255.255.255.128 -DefaultGateway $GW -Dns 8.8.8.8 -Confirm:$false

# Deploy an AutoAD OVA and add the existing AutoAD.vdmk. DRS will take care of the rest.
New-VM -VMHost $ESXi_Host -Name "AutoAD_Temp" -Datastore 'Images' -NumCPU 2 -CoresPerSocket 1 -MemoryGB 4 -SkipHardDisks -Confirm:$false
New-HardDisk -DiskPath "[Images] AutoAD.vmdk" -VM "AutoAD"

# Transform the VM into a template as we need to set static IP
New-Template -Name "AutoAD-Templ" -VM "AutoAD_Temp"

# Deploy the final AutoAD with Static IP
New-VM -VMHost $ESXi_Host -Name "AutoAD" -Datastore 'vmContainer1' -Template "AutoAD-Templ" -OSCustomizationSpec "PowerCliOnly" | Set-OSCustomizationNicMapping -Position 1 -IpMode UseStaticIP -IpAddress $AutoAD -SubnetMask 255.255.255.128 -DefaultGateway $GW -Dns 8.8.8.8 -Confirm:$false

# Close the VMware connection
disconnect-viserver * -Confirm:$false

# ********************* PE level ***********************************************
# Confiure PE to use AutoAD for authentication





# **********************************************************************************
# Deploy Prism Central
# **********************************************************************************


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


