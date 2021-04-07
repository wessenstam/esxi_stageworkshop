# ESXi Staging
Staging ESXi HPOC systems

## Remark
Below is still in scaffolding!!! Nothing is yet GA!!

## High level description
This repo is to have the possibility to create an ESXi staging possibility for ESXi environments.
As ESXi not supports the same Nutanix products as AHV, this staging script will only install and configure:
1. Prism Central
2. Calm
3. Files
4. Objects
5. Era
6. Leap

## Staging requirements
As the ESXi environment can not be 100% configured to the needs using REST APIs, the machine which is being used to run the installation must have Docker installed.
Reason for this is that the configuration of ESXi will be done using Powershell using the VMware PowerCLI (https://github.com/vmware/powerclicore).
The cluster has been reserved and ran via RX manager

## Usage
Follow these steps to get the staging running:
1. Change the **environment.env** file with the needed parameters (password and the IP address of the PE instance)
2. Run the **stage_esxi.sh** file

## Detailed run
The script will do the following:
1. Using REST API for PE:

   1. Accept the EULA
   2. Disable Pulso
   3. Change the Storage Pool name to SP01
   4. Change the defafult-XXX storage container name to default
   5. Create an Images storage container
   6. Mount the Images storage container to all ESXi hosts

2. Using native Powershell for VMware to:

   1. Configure the secondairy network
   2. Enable DRS
   3. Deploy AutoAD for DNS and Authentication

3. Using REST API for PE:

   1. Configure Authentication
   2. Upload needed ISO and Disk images into the Images datastore

4. Using REST API for PC:
   
   1. Change the password to the same password as PE
   2. Accept the EULA
   3. Disable Pulse
   4. Add DNS Servers (AutoAD)
   5. Set Authentication
   6. Create the roles (Rolemapping)
   7. Import Images from PE
   8. Enable Calm
   9. Enable Objects
   10. Run LCM
   11. Create Projects
   12. Create PC Admin and role
   13. Deploy and configure Era
