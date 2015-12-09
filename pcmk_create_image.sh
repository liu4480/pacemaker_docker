#! /bin/bash

ret=`cat /etc/issue | grep -i suse`
is_suse=$?
if [ $is_suse -eq 0 ]; then
	./pcmk_create_opensuse_image.sh
else
	./pcmk_create_centos_image.sh
fi
