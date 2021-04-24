#!/usr/bin/env bash
##########################################################################################################################################################################
# main.sh is the mother of which we'll start all the subscripts
##########################################################################################################################################################################
# Created by Technical Enablement - 2019
# ------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# 5th of April 2019 - Willem Essenstam - Started the initial scripting
# 10th of April 2019 - Willem Essenstam - got vCenter installation working
# 11th of April 2019 - Willem Essenstam - Working on the test on a new cluster
# 15th of April 2019 - Willem Essenstam - Working on the installation and remodeling the script's layout
# 16th of April 2019 - Willem Essenstam - Working on the checking routine to see if the script is run in HPOC or not
# 26th of June 2019 - Willem Essenstam - Getting the vCenter registration sorted
#                                        Getting the Images datastore sorted
#                                        Getting the Images uploads sorted
#                                        Getting the upload of Prism Central sorted
#                                        Getting the install of Prism Central sorted
#                                        Getting the registration into PC sorted
##########################################################################################################################################################################


# Get the global_var loaded and the commonly to be used functions
. scripts/global_vars.sh
. scripts/lib.common.sh
. scripts/lib.vmware.sh

# -----------------------------------------------------------------------------------
# Call the Eula stuff
# -----------------------------------------------------------------------------------
eula_pulse

# -----------------------------------------------------------------------------------
# Call the hpoc_check to see if we are in HPOC environment.
# -----------------------------------------------------------------------------------
hpoc_check

# We are not in HPOC as we received an return 1 from the hpoc_check function
# Building the vCenter environment so we can proceed
if [ $? -eq 1 ]; then 

    # -----------------------------------------------------------------------------------
    # Create the vcsa storage needed to install VCSA
    # -----------------------------------------------------------------------------------
    vcsa_storage  && \

    # -----------------------------------------------------------------------------------
    # Install the VCSA
    # -----------------------------------------------------------------------------------
    vcsa_install && \

    # -----------------------------------------------------------------------------------
    # Cleanuop after the script has run
    # -----------------------------------------------------------------------------------
    cleanup_vmware && \

    # -----------------------------------------------------------------------------------
    # Register vCenter
    # -----------------------------------------------------------------------------------
    register_vcenter
fi

# Now we can start with the general stuff for all environments
# Order
# 1. Domain Controller at .50!!! .40 is vCenter
# 2. Create networks?
# 3. Create DHCP server?
# 4. Create Images datastore and mount to all hosts
# 5. Upload images to a datastore
# 6. Prism Central
#     - Upload
#     - Install

# -----------------------------------------------------------------------------------
# Call upload the PC stuff 
# -----------------------------------------------------------------------------------
upload_pc && \
# -----------------------------------------------------------------------------------
# Call create the images storage container stuff 
# -----------------------------------------------------------------------------------
vcsa_storage "Images" && \



# -----------------------------------------------------------------------------------
# Call get the authentication to vCenter stuff 
# -----------------------------------------------------------------------------------
auth_vcenter && \

# -----------------------------------------------------------------------------------
# Call create the networks stuff 
# -----------------------------------------------------------------------------------
# create_networks && \

