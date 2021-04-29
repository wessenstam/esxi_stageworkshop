# Set some environmental variables
Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -DefaultVIServerMode:Multiple -confirm:$false | Out-Null
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP:$false -confirm:$false | Out-Null

# Get the modules in
import-module ./modules

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

$cluster_name=Get-Clustername -password $password -PE_IP $PE_IP

echo $cluster_name
remove-module modules