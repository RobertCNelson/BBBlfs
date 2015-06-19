#!/bin/bash

diff(){
	awk 'BEGIN{RS=ORS=" "}
		{NR==FNR?a[$0]++:a[$0]--}
		END{for(k in a)if(a[k])print k}' <(echo -n "${!1}") <(echo -n "${!2}")
}

is_file_exists(){
	local f="$1"
	[[ -f "$f" ]] && return 0 || return 1
}

is_online(){
	wget -q --tries=5 --timeout=20 http://google.com
	if [[ $? -eq 0 ]]; then
		return 0
	else
		return 1
	fi
}

usage(){
	echo "Usage: $0 [ debian | ubuntu | input.img.xz ]"
	echo "Supported images are just in .img.xz format."
	exit 1
}

reset_bbb_usb () {
	echo "Attempting to reset Downstream BBB"
	if [ ! -d /sys/class/leds/usb_hub_power ] ; then
		devmem2 0x47401c60 b 0x00
	else
		echo 0 > /sys/class/leds/usb_hub_power/brightness
	fi

	sleep 1
	echo "usb1" > /sys/bus/usb/drivers/usb/unbind
	sleep 20

	echo "usb1" > /sys/bus/usb/drivers/usb/bind
	sleep 1

	if [ ! -d /sys/class/leds/usb_hub_power ] ; then
		devmem2 0x47401c60 b 0x01
	else
		echo 255 > /sys/class/leds/usb_hub_power/brightness
	fi
	sleep 2
}

echo
input=$1

if [[ $# -eq 0 ]]
then
	read -p "You did not provide an image to flash. Do you want me to download the latest Debian image from beagleboard.org? [yY]" -n 1 -r
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		if ( ! is_online )
		then
			echo "You do not have network connectivity!"
			exit 1
		fi
		echo
		page="$(curl -s -O http://beagleboard.org/latest-images)" 
		line="$(cat latest-images | grep debian | head -n1)"
		url="$(echo $line | cut -c7-)"
		url="${url%?}"
		rm index.html
		rm latest-images
		wget -O flash.img.xz $url
		input="flash.img.xz"
	fi
else
	input=$1
fi

if [ ! \( "$input" = "debian" -o "$input" = "ubuntu" \) ]
then

	if ( ! is_file_exists "$input" )
	then
		echo "Please provide an existing flash file."
		usage
		exit 1
	fi

	echo "We are flashing this all mighty BeagleBone Black with the image from $input!"

fi
echo "Please do not insert any USB Sticks"\
		"or mount external hdd during the procedure."
echo 

if [ ! -d /sys/class/leds/usb_hub_power ] ; then
	if [ ! -f /usr/bin/devmem2 ] ; then
		wget --directory-prefix=/tmp/ http://ports.ubuntu.com/pool/universe/d/devmem2/devmem2_0.0-0ubuntu1_armhf.deb
		dpkg -i /tmp/devmem2_0.0-0ubuntu1_armhf.deb
	fi
fi

#read -p "When the BeagleBone Black is connected in USB Boot mode press [yY]." -n 1 -r
#echo
#if [[ $REPLY =~ ^[Yy]$ ]]
#then
	before=($(ls /dev | grep "sd[a-z]$"))

	reset_bbb_usb

	if ( ! is_file_exists usb_flasher)
	then
		echo "Please make the project then execute the script!"
		exit 1
	fi

	echo
	echo "Putting the BeagleBone Black into flashing mode!"
	echo

	sudo ./usb_flasher
	rc=$?
	if [[ $rc != 0 ]];
	then
		echo "The BeagleBone Black cannot be put in USB Flasing mode. Send "\
				"logs to vvu@vdev.ro together with the serial output from the"\
				"BeagleBone Black."
		exit $rc
	fi

	echo -n "Waiting for the BeagleBone Black to be mounted"
	for i in {1..12}
	do
		echo -n "."
		sleep 1
	done
	echo 

	after=($(ls /dev | grep "sd[a-z]$"))
	bbb=($(diff after[@] before[@]))
	
	if [ -z "$bbb" ];
	then
		echo "The BeagleBone Black cannot be detected. Either it has not been"\
				" mounted or the g_mass_storage module failed loading. "\
				"Please send the serial log over to vvu@vdev.ro for debugging."
		exit 1
	fi
	
	if [ ${#bbb[@]} != "1" ]
	then
		echo "You inserted an USB stick or mounted an external drive. Please "\
			"rerun the script without doing that."
		exit 1
	fi

#	read -p "Are you sure the BeagleBone Black is mounted at /dev/$bbb?[yY]" -n 1 -r
#	echo

#	if [[ $REPLY =~ ^[Yy]$ ]];
		parts=($(ls /dev | grep "$bbb[1,2]"))
#		then
			for index in ${!parts[*]}
			do
				sudo umount /dev/${parts[$index]}
		done
		echo "Flashing now, be patient. It will take ~5 minutes!"
		echo
#		if [ \( "$input" = "debian" -o "$input" = "ubuntu" \) ]
#		then
#			sudo ./bbb-armhf.sh $bbb $input
#		else

			#if [ -f /usr/bin/bmaptool ] ; then
			#	bmaptool create -o /tmp/image.bmap $input
			#	bmaptool copy --bmap /tmp/image.bmap $input /dev/$bbb
			#else
				xzcat $input | sudo dd of=/dev/$bbb bs=1M
			#fi

sync
reset_bbb_usb

#			echo
#			echo "Resizing partitons now, just as a saefty measure if you flash 2GB image on 4GB board!"
#			echo -e "d\n2\nn\np\n2\n\n\nw" | sudo fdisk /dev/$bbb > /dev/null
#		fi
#		sudo e2fsck -f /dev/${bbb}2
#		sudo resize2fs /dev/${bbb}2
#		echo
#        echo "Please remove power from your board and plug it again."\
#				"You will boot in the new OS!"
#	fi
#fi
