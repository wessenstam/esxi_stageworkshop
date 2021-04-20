# ESXi Staging
Staging ESXi HPOC systems

## Remark
Below is still in scaffolding!!! Nothing is yet GA!!

## TODO:
Below items are NOT YET in the script:
- Full LCM cycle
- Add VMware as a provider for Calm
- Create Projects
- Create PC Admin and role
- Deploy and configure Era


## High level description
This repo is to have the possibility to create an ESXi staging possibility for ESXi environments.
As ESXi not supports the same Nutanix products as AHV, this staging script will only install and configure/enable:
1. Prism Central
2. Calm
3. Files
4. Objects
5. Era
6. Leap
7. Karbon

## Staging requirements
As the ESXi environment can not be 100% configured to the needs using REST APIs, PowerShell is being used. To run Powershell two paths can be followed:

1. Using Native installation of PowerShell on the Machine that is being used.
2. Using a Docker container that uses the VMware PowerCli

### Native installation of Powershell
For Windows this is natively already installed, so there is nothing that needs to be done on that part. 
If the machine is Mac or Linux, it is still possible to install PowerShell. Please follow the article to get PowerShell installed for your O/S

1. Linux: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7.1
2. MacOS: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-macos?view=powershell-7.1

For Linux and MacOS, preferred way is using the container version of the PowerCLI. Reason is that during the building of the script, strange behaviours have been seen where intermittent errors where shown when running the script. A RC has so far not been found...

### Native installation of PowerCLI
Independent of your O/S and running Native PowerShell, you have to follow this article to get the VMware POwerCLI installed https://developer.vmware.com/powercli/installation-guide. 

### Docker version of PowerCLI
For this type of running the script, Docker has to be installed on your machine. There are a lot of articles on how to install Docker on your O/S. Follow this article to install Docker for your O/S https://docs.docker.com/get-docker/. After you have installed Docker, you can use the following command to run the script: **docker run --rm -it -v ${PWD}:/script vmware/powerclicore pwsh /script/stage_esxi.ps1** .Where:

- --rm; after the container has stopped, remove it from the docker environment
- -it; run in interactive mode, show the console output of the script
- -v; "mount" the following path **${PWD}** (current directory) to the **/script** diectory INSIDE the container
- vmware/powerclicore; the name of the container image that is going to be run. It will be downloaded automatically if it doesn't exist on the machine.
- /script/stage_esxi.ps1; the name of the script including the location **INSIDE** the container. As we have mounted, using the **-v** parameter, the location on the machine that holds the script file to /script in the container, the container needs to be told the absolute full path.

> If you want to know more on the container, please read this https://github.com/vmware/powerclicore. 

> An extra Module has been added to the container. The Module is called Posh-SSH (https://github.com/darkoperator/Posh-SSH). This makes it possible to use SSH with username and password to manipulate Linux based machines. The script is using it to manipulate the Era instanace for setting its static IP Address. Besides the extra Module the example scripts have been removed from the container. How the container is build, please consult the Dockerfile in the root of the Repo.
## Usage
Follow these steps to get the staging running:

1. Run **git pull https://github.com/wessenstam/esxi_stageworkshop** to pull the script and needed information
2. CD into the location where the GitHub Repo has been pulled
3. Create a file named **environment.env** with the needed parameters. These parameters are *<PE password>,<IP address of the PE instance>* **example; ThisisSecret,10.10.10.10**
4. Save the file
4. Run the Powershell script **stage_esxi.ps1** via one of the two options described earlier

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
   2. Enable DRS and disable Admission Control
   3. Upload ISO Images and OVA Templates in a newly created Content Library
   4. Deploy AutoAD for DNS and Authentication

      > During this step, in rare cases, the AutoAD is not starting due to Powershell. It needs to have a user interact with the script. If the script is stuck for 45 minutes it will stop. To make sure the script progresses, check the logs (in the console). After approx 15 minutes the script should progress to the next steps. If not, please open the UI of the AutoAD VM and interact with the VM. After that the script will pick up the AutoAD progress and move forward.

   5. Deploy CentOS 7 VM and turns it into a Template so it can be used with Calm
   6. Deploy the WindowsTools VM

3. Using REST API for PE:

   1. Configure Authentication
   2. Create Roles for the SSP Admin group from AD as Cluster Admin
   3. Deploy Prism Central

4. Using REST API for PC:
   
   1. Change the password to the same password as PE
   2. Accept the EULA
   3. Disable Pulse
   4. Add DNS Servers (AutoAD)
   5. Set Authentication
   6. Create the roles (Rolemapping)
   7. Enable Karbon
   8. Enable Calm
   9. Enable Objects
   10. Run LCM (Inventory and Upgrade)
   11. Create VMware as the Provider for Calm
   12. Create Projects
   13. Create PC Admin and role
   14. Deploy and configure Era
