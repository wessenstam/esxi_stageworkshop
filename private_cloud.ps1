# Set some environmental variables
Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -DefaultVIServerMode:Multiple -confirm:$false | Out-Null
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP:$false -confirm:$false | Out-Null

# are we running natively or from the docker container?
if (Test-Path -Path ./environment.env -PathType Leaf){
    $parameters=get-content "./environment.env"
    import-module ./Modules/modules
}else{
    $parameters=get-content "/script/environment.env"
    import-Module /script/Modules/modules
}


# **********************************************************************************
# Setting the needed variables
# **********************************************************************************
# Are we running from native Powershell or via the PowerCLI docker container
if (Test-Path -Path ./environment.env -PathType Leaf){
    $parameters=get-content "./environment.env"
}else{
    $parameters=get-content "/script/environment.env"
}

$password=$parameters.Split(",")[0]
$PE_IP=$parameters.Split(",")[1]
$ip_subnet=$PE_IP.Substring(0,$PE_IP.Length-3)

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


# Get the clustername
$datavar=@{
    PE_IP = $PE_IP
    ip_subnet = $ip_subnet
    password = $password
    nfs_host = $nfs_host
    AutoAD = $AutoAD
    VCENTER = $VCENTER
    PC_IP = $PC_IP
    Era_IP = $Era_IP
    GW = $GW
    vlan = $vlan
}

$cluster_name=GetClustername -IP $PE_IP -Header $Header_NTNX_Creds

Write-Output "*************************************************"
Write-Output "Concentrating on Nutanix PE environment ($cluster_name).."
Write-Output "*************************************************"

# Set all needed variables in the global datavar object
$datavar=@{
    PE_IP = $PE_IP
    ip_subnet = $ip_subnet
    password = $password
    nfs_host = $nfs_host
    AutoAD = $AutoAD
    VCENTER = $VCENTER
    PC_IP = $PC_IP
    Era_IP = $Era_IP
    GW = $GW
    vlan = $vlan
    cluster_name = $cluster_name
}
<#
# **************************************
# Initial PE configuration
# **************************************

# Accept the Eula
$response=AcceptEula -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Disable Pulse
$response=DisablePulse -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Change the default SP Name to Sp1
$response=ChangeSPName -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Change the default SP Name to Sp1
$response=RenameDefaultCNTR -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Create Images container
$response=CreateImagesCNTR -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response

# Mount Images container
$response=MountImagesCNTR -IP $PE_IP  -Header $Header_NTNX_Creds
Write-Output $response
#>
Write-Output "*************************************************"
Write-Output "Concentrating on VMware environment ($VCENTER).."
Write-Output "*************************************************"

# **************************************
# Initial VMware configuration
# **************************************

# Connect to vCenter
$response=ConnectVMware -vcenter $VCENTER -password $password
write-output $response

#Enable DRS and disable Admission control
$response=EnableDRSDisableAdmissionContol -vcenter $VCENTER -password $password
write-output $response

# Create the Secondary network in the correct VLAN
$vm_cluster_name=$response.substring($response.IndexOf("(")+1,$response.length-$response.IndexOf("(")-3)
<#
$response=CreateSecondaryNetwork -vm_cluster_name $vm_cluster_name -vlan $vlan
Write-Output $response

Write-Output "Uploading needed images"
# Create Content Libarary
New-ContentLibrary -Name "deploy" -Datastore "Images" | Out-Null

# Upload needed images
$images=@('esxi_ovas/AutoAD_Sysprep.ova','esxi_ovas/CentOS.ova','esxi_ovas/Windows2016.ova')
foreach($image in $images){
    $response=UploadImage -image $image -nfs_host $nfs_host
    Write-Output $response
}

# Deploy the AutoAD and wait till ready before moving forward
$response=DeployAutoAD -vm_cluster_name $vm_cluster_name -AutoAD $AutoAD
Write-Output $response

# Deploy the CentOS and Windows 2016 templates
$templates=@('Windows2016','CentOS')
foreach($template in $templates){
    $response=DeployVMTemplate -vm_cluster_name $vm_cluster_name -templ_name $template
    write-output $response
}
#>
# Deploying the WinToolsVM 1) Upload into Content Libarary; 2) Deploy the VM
$response=UploadImage -image 'esxi_ovas/WinTools-AHV.ova' -nfs_host $nfs_host
Write-Output $response

$response=DeployWinToolsVM -vm_cluster_name $vm_cluster_name
write-output $response

# Disconnecting from the vCenter
$response=DisconnectvCenter
write-output $response

# Remove the loaded modules from memory
remove-module modules