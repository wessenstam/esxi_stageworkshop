#!/bin/bash
# Script for converting the QCOW2 files to vmdk files so they can be used with VMware

# Mounting the nfs share that holds the QCOW2 files
mount -t nfs 10.42.194.11:/workshop_staging /media/nfs_workshop

# Create converted directory if not exists
if [ ! -d "/media/nfs_workshop/converted" ]; then
	mkdir -p /media/nfs_workshop/converted
fi

# Get the to be converted qcow2 files in an array
images_ar=($(ls /media/nfs_workshop/[ACTW]*.qcow2 | cut -d "/" -f 4))

# Loop through the array
_count=0
_size_ar="${#images_ar[@]}"
input_dir="/media/nfs_workshop/"
output_dir="/media/nfs_workshop/converted/"
while [ $_count -lt $_size_ar ]; do
	output="${images_ar[$_count]%.*}.vmdk"
	input="${images_ar[$_count]%.*}.qcow2"
	echo "Converting ($_count/$_size_ar) ${images_ar[$_count]} to $output_dir$output and making a small change to the VMDK"
	qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized $input_dir$input $output_dir$output
	printf '\x03' | dd conv=notrunc of=$output_dir$output bs=1 seek=$((0x4))
	let _count+=1
done
