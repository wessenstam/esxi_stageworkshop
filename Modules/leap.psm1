# Specific Leap functions for the deployment of Nutanix on ESXi
# 30-04-2021 - Willem Essenstam - Nutanix

# Debug Function
function testleap{
    param(
        [string] $text
    )
    write-host "You reached module leap_mod.psm1"
    return $text
}

# Enable Leap
Function EnableLeap{
    param(
        [string] $IP,
        [object] $Header
    )

    Write-Host "Checking if Leap can be enabled"

    # Check if the Objects have been enabled

    $APIParams = @{
        method="GET"
        Uri="https://$($IP):9440/api/nutanix/v3/services/disaster_recovery/status?include_capabilities=true"
        ContentType="application/json"
        Header = $Header
    } 
    $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).service_capabilities.can_enable.state
    if ($response -eq $true){
        Write-Host "Leap can be enabled, so progressing."
        $APIParams = @{
            method="POST"
            Body='{"state":"ENABLE"}'
            Uri="https://$($IP):9440/api/nutanix/v3/services/disaster_recovery"
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).task_uuid
        # We have been given a task uuid, so need to check if SUCCEEDED as status
        $APIParams = @{
            method="GET"
            Uri="https://$($IP):9440/api/nutanix/v3/tasks/"+$response
            ContentType="application/json"
            Header = $Header
        } 
        $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
        # Loop for 2 minutes so we can check the task being run successfuly
        if ($response -NotMatch "SUCCEEDED"){
            $counter=1
            while ($response -NotMatch "SUCCEEDED"){
                Start-Sleep 10
                $response=(Invoke-RestMethod @APIParams -SkipCertificateCheck).status
                if ($counter -eq 12){
                    return "Waited two minutes and Leap didn't get enabled! Please check the PC UI for the reason."
                }else{
                    return "Leap has been enabled"
                }
            }
        }else{
            return "Leap has been enabled"
        }
    }else{
        return "Leap can not be enabled! Please check the PC UI for the reason."
    }
}