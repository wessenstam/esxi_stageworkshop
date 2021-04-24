#####################################################################################
# Pre_reqs file to have: nfs and the exports ready that are to be used by the 
# staging script
#####################################################################################

#####################################################################################
# Installing NFS server
#####################################################################################
# Upgrading the system
yum update -y && yum upgrade -y

# Install NFS materials
yum install nfs-utils -y

# Configuring the system so NFS server will run at boot and start the needed daemons
systemctl enable rpcbind
systemctl enable nfs-server
systemctl enable nfs-lock
systemctl enable nfs-idmap
systemctl start rpcbind
systemctl start nfs-server
systemctl start nfs-lock
systemctl start nfs-idmap

# Open the firewall for NFS
firewall-cmd --permanent --zone=public --add-service=nfs
firewall-cmd --permanent --zone=public --add-service=mountd
firewall-cmd --permanent --zone=public --add-service=rpc-bind
firewall-cmd --reload

# Install jq as we call this a lot
yum install -y jq

# Disable SELINUX
sed -i 's/enforcing/disabled/g' /etc/selinux/config

# Install nginx server
yum install -y nginx
systemctl enable nginx
systemctl start nginx

# Open the firewall for NFS
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --reload

# Create the needed location for the images
mkdir -p /media/images

# Creating the /etc/exports file and restart the NFS server
echo '/media/images    10.42.*.*(ro,sync,no_root_squash,no_all_squash)' > /etc/exports
systemctl restart nfs-server

# Grabbing teh images from the S3 location
# TODO: We might be needing some other location as well....

# Reboot is needed!!!!
shutdown -r



