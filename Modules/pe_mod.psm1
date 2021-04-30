# Specific PE functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testpe{
    param(
        [string] $text
    )
    write-host "You reached module pe_mod.psm1"
    return $text
}

# Change the name of the Storage Pool to SP1
function ChangeSPName {
    param (
        [string] $IP,
        [object] $Header
    )
    # First get the Disk IDs
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/storage_pools?sortOrder=storage_pool_name"
        ContentType="application/json"
        Header = $Header
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
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/storage_pools?sortOrder=storage_pool_name"
        ContentType="application/json"
        Body=$Body
        Header = $Header
    }

    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
    if ($response="True"){
        return "Storage Pool has been renamed"
    }else{
        return "Storage Pool has not been renamed"
    }

}

# Change the name of the defaulxxxx storage container to Default
Function RenameDefaultCNTR{
    param (
        [string] $IP,
        [object] $Header
    )

    # Get the ID and UUID of the default container first
    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/storage_containers"
        ContentType="application/json"
        Header = $Header
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
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/storage_containers"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    if ($response = "True"){
        return "Default Storage Container has been updated"
    }else{
        return "Default Storage Container has NOT been updated"
    }
}
# Create the Images datastore
Function CreateImagesCNTR{
    param (
        [string] $IP,
        [object] $Header
    )
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
    Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/storage_containers"
    ContentType="application/json"
    Body=$Payload
    Header = $Header
    }
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    if ($response = "True"){
        return "Images Storage Container has been created"
    }else{
        return "Images Storage Container has NOT been created"
    }

}


# Mount the Images container to all ESXi hosts
Function MountImagesCNTR{
    param (
        [string] $IP,
        [object] $Header
    )
    # Get the ESXi Hosts UUIDS

    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v2.0/hosts/"
        ContentType="application/json"
        Header = $Header
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
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/containers/datastores/add_datastore"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }
    try{
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
        return "The Images container has been mounted on all ESXi hosts"
    }catch{
        return "The Images container has not been mounted on all ESXi hosts"
    }
}