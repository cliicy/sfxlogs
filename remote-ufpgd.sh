#!/bin/bash

source ./lib/automator
source ./lib/sfx-common
source cfg/sfx-config

# gold image
ssh ${goldimage_server} "mkdir -p ${gdimg_case_dir}" 
scp gd-case.sh tcn@${goldimage_server}:${gdimg_case_dir} 
scp new_reg_prepare.sh tcn@${goldimage_server}:${gdimg_case_dir} 
scp cgdimage-logs.sh  tcn@${goldimage_server}:${gdimg_case_dir}
scp do-remote-things.sh  tcn@${goldimage_server}:${gdimg_case_dir}
scp -r ./lib/automator tcn@${goldimage_server}:${gdimg_case_dir}
scp -r ./cfg/sfx-config tcn@${goldimage_server}:${gdimg_case_dir}
ssh ${goldimage_server} "${bin_bash} ${gdimg_case_dir}/do-remote-things.sh"

