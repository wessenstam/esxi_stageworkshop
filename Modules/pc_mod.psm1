# Specific PC functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testpc{
    param(
        [string] $text
    )
    write-host "You reached module pc_mod.psm1"
    return $text
}

# Reset PC Password to match PE's password
Function ResetPCPassword{
    param(
        [string] $IP,
        [string] $password,
        [object] $Header
    )
    # Set Prism Central password to the same as PE

    $Payload='{"oldPassword":"Nutanix/4u","newPassword":"'+$password+'"}'
    $APIParams = @{
        method="POST"
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/utils/change_default_system_password"
        ContentType="application/json"
        Body=$Payload
        Header = $Header
    }

    # Need to use the Default creds to get in and set the password, only once

    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)
    if ($response = "True"){
        return "PC Password has been changed to the same as PE"
    }else{
        return "PC Password has NOT been changed to the same as PE. Exiting script."
        exit 2
    }
}

# Add NTP servers
Function PCAddNTPServers{
    param(
        [string] $IP,
        [object] $Header
    )
    Write-Host "Adding NTP Servers"
    foreach ($ntp in (1,2,3)){
        if ($ntp -ne $null){
            $APIParams = @{
                method="POST"
                Body='[{"hostname":"'+$ntp+'.pool.ntp.org"}]'
                Uri="https://$($IP):9440/PrismGateway/services/rest/v1/cluster/ntp_servers/add_list"
                ContentType="application/json"
                Header = $Header
            } 
            $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).value
            if ($response = "True"){
                Write-Host "NTP Server $ntp.pool.ntp.org added"
                $Fail="No"
            }else{
                Write-Host "NTP Server $ntp.pool.ntp.org not added"
                $Fail="Yes"
            }
        }
    }
    if ($Fail -Match "Yes"){
        return "All NTP servers have been added to PC"
    }else{
        return "Issues have risen during the adding of the NTP Servers to PC"
    }
}

# LCM run inventory and upgrade all, except PC and NCC
Function PCLCMRun{
    param(
        [string] $IP,
        [object] $Header
    )

    Write-Host "Running LCM Inventory"
    # RUN Inventory
    $Payload='{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"perform_inventory\",\"args\":[\"http://download.nutanix.com/lcm/2.0\"]}}"}'
    $APIParams = @{
        method="POST"
        Body=$Payload
        Uri="https://$($IP):9440/PrismGateway/services/rest/v1/genesis"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck) 
    $task_id=($response.value.Replace(".return","task_id")|ConvertFrom-JSON).task_id

    # Wait till the LCM inventory job has ran using the task_id we got earlier
    $APIParams = @{
            method="GET"
            Uri="https://$($IP):9440/api/nutanix/v3/tasks/"+$task_id
            ContentType="application/json"
            Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status

    $counter=1
    While ($response -NotMatch "SUCCEEDED"){
        Write-Host "Waiting for LCM inventroy to be completed ($counter/45 mins)."
        Start-Sleep 60
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
        if ($counter -eq 45){
            write-out "We have waited for 45 minutes and the LCM did not finish."
            write-out "Please use the PC UI to update the environment."
            Break
        }
        $counter++
    }
    if ($countert -eq 45){
        Write-Host "LCM inventory has failed"
    }else{
        Write-Host "LCM Inventory has run successful. Progressing..."
    }


    # What can we update?
    $APIParams = @{
        method="POST"
        Body='{}'
        Uri="https://$($IP):9440/lcm/v1.r0.b1/resources/entities/list"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

    [array]$uuids=$response.data.entities.uuid
    [array]$versions=""
    [array]$updates=""
    $count=0
    foreach ($uuid in $uuids){
        try{
            [array]$version = (($response.data.entities | where-object {$_.uuid -eq $uuids[$count]}).available_version_list.version | sort-object)
            $software=($response.data.entities | where-object {$_.uuid -eq $uuids[$count]}).entity_model
            if ($software -NotMatch "PC" -And $software -NotMatch "NCC"){ # Remove PC and NCC from the upgrade list
                [array]$updates += $software+","+$uuid+","+$version[-1]
            }
        }catch{
            Write-Host "No update for $software"
        }
        $count ++
    }
    # Build the JSON Payload
    $json_payload_lcm='['
    foreach ($update in $updates){
        if($update.split(",")[1] -ne $null) {
            $json_payload_lcm +='{"version":"'+$update.Split(",")[2]+'","entity_uuid":"'+$update.Split(",")[1]+'"},'
        }
    }
    $json_payload_lcm = $json_payload_lcm.subString(0,$json_payload_lcm.length-1) +']'

    # Can we update?
    $APIParams = @{
        method="POST"
        Body=$json_payload_lcm
        Uri="https://$($IP):9440/lcm/v1.r0.b1/resources/notifications"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

    if ($response.data.upgrade_plan.to_version.length -lt 1){
        Write-Host "LCM can not be run as there is nothing to upgrade.."
    }else{
        Write-Host "Firing the upgrade to the LCM platform"
        $json_payload_lcm_upgrade='{"entity_update_spec_list":'+$json_payload_lcm+'}'
        $APIParams = @{
            method="POST"
            Body=$json_payload_lcm_upgrade
            Uri="https://$($IP):9440/lcm/v1.r0.b1/operations/update"
        
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck)

        $taskuuid=$response.data.task_uuid

        # Wait loop for the TaskUUID to check if done
        $APIParams = @{
            method="GET"
            Uri="https://$($IP):9440/api/nutanix/v3/tasks/"+$taskuuid
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
        # Loop for 2 minutes so we can check the task being run successfuly
        $counter=1
        while ($response -NotMatch "SUCCEEDED"){
            Write-Host "LCM Upgrade still running ($counter/45 mins)...Retrying in 1 minute."
            Start-Sleep 60
            $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
            if ($counter -eq 45){
                break
            }
            $counter ++
        }
        if ($counter -eq 45){
            return "Waited 45 minutes and LCM didn't finish the updates! Please check the PC UI for the reason."
        }else{
            return "LCM Ran successfully"
        }
    }
}