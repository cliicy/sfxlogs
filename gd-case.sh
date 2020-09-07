#!/bin/bash

source ./automator
source ./sfx-config

sfx_logs=${sfx_logs-"/usr/bin/sfx-logs"}
SW_VERSION=${SW_VERSION-latest}
bundle_dir=${bundle_dir-`pwd`/bundle_logs}
local_share=${local_share-share_bj}
fpga_base_dir=${local_share}/releases/vanda/B17A
fpga_version=${fpga_version-4759}


timestamp=`date +%Y%m%d_%H%M%S`
log_dir=${bundle_dir}/${timestamp}

if [ ! -d ${log_dir} ]; then
    mkdir -p ${log_dir}
fi
echo ${log_dir} > log_dir.out

install_drv() {
    cur_drv=`sudo sfx-status | grep "Software Revision"  |awk '{print $3}'`
    full_version=${drv_version##rc_}
    p1_ver=`echo $full_version | cut -d '-' -f1`
    p2_ver=`echo $full_version | cut -d '-' -f2`
    short_ver=${p1_ver}-${p2_ver##r}
    echo "++${cur_drv}++  --${short_ver}--"
    if [ "${cur_drv}" != "${short_ver}" ];
    then
        init_network_env
        ${install_drv_cmd}
        if [ $? -eq 0 ]; then
            echo "rpm/deb install succeed"
        else
            echo "not Found build, will install again with source package"
            ${install_drv_cmd} ${src_install}
            echo "src rpm/deb install succeed"
        fi
    fi
}

collect_sys_info ${log_dir}
# install driver
install_drv
sudo ${sfx_logs} > ${log_dir}/sfxlogs_install_drv.out  2>&1
mv *_bundle.tar.gz ${log_dir}/bundle_install_drv.tar.gz 
