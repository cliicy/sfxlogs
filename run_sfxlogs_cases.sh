#!/bin/bash

source ./lib/automator
source ./lib/sfx-common
source cfg/sfx-config

dev_name=${dev_name-sfdv0n1}
disk_csd=/dev/${dev_name}
fs_types=${fs_types-"ext4 xfs"}
sfx_logs=${sfx_logs-"/usr/bin/sfx-logs"}

timestamp=`date +%Y%m%d_%H%M%S`
log_dir=${bundle_dir}/${timestamp}

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
        fi
    fi
}

if [ ! -d ${log_dir} ]; then
    mkdir -p ${log_dir}
fi

collect_sys_info ${log_dir}

# install driver
if [ "${ck_install_drv}" == "1" ]; then
    install_drv
    sudo ${sfx_logs} > ${log_dir}/sfxlogs_install_drv.out  2>&1
    mv *_bundle.tar.gz ${log_dir}/sfxlogs_install_bundle.tar.gz 
fi

multi_cards=`lsblk | grep sfdv | grep -v p |awk '{print $1}'`

# run fio on block device
if [ "${ck_rawdisk}" == "1" ]; then
    echo "on device device, run fio"
    for card in ${multi_cards[@]};
    do
        disk_csd=/dev/${card}
        echo "raw disk umount ${disk_csd}"
        sudo umount ${disk_csd} 
        echo y | sudo sfx-nvme format ${disk_csd} -s 1
        sudo tool/fio --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --name=init_seq_${card} --rw=write --bs=128k --iodepth=32 --runtime=${fio_runtime} --filename=/dev/${card} --output=${log_dir}/init_write_128k_dq32_${card}.log
        sudo ${sfx_logs} > ${log_dir}/sfxlogs_rawdisk_${card}.out  2>&1
        mv *_bundle.tar.gz ${log_dir}/sfxlogs_rawdisk_${card}_bundle.tar.gz
    done
fi

# mkfs ext4/xfs on device, run fio
if [ "${ck_fsdisk}" == "1" ]; then
    echo "no partition mkfs ext4/xfs on device, run fio"
    for card in ${multi_cards[@]};
    do
        disk_csd=/dev/${card}
        mount_point=${mount_dir}/${card}
        echo "${mount_point}"
        sudo umount ${disk_csd} 

        if [ ! -d ${mount_point} ]; then
            mkdir -p ${mount_point}
        fi

        for fs in ${fs_types};
        do 
            echo "filesystem umount ${disk_csd}"
            sudo umount ${disk_csd} 
            if [ "${fs}" == "xfs" ]; then
                sudo mkfs -t ${fs} -f ${disk_csd}
            else
                sudo mkfs -t ${fs} ${disk_csd}
            fi
            if [ ! -d ${mount_part_point} ]; then
               mkdir -p ${mount_part_point}
            fi
            sudo mount ${disk_csd} ${mnt_opt} ${mount_point}
            sudo tool/fio --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --time_based  --random_generator=tausworthe --runtime=${fio_runtime} --output=${log_dir}/write_128k_dq64_${card}_${fs}.log --directory=${mount_point} --size=30000M --bs=128k --name=ext4_write8_${card}_${fs} --rw=write --numjobs=8 --iodepth=64
            sleep 5
            sudo ${sfx_logs} > ${log_dir}/sfxlogs_write8_128k_dq64_${card}_${fs}.out  2>&1
            mv *_bundle.tar.gz ${log_dir}/sfxlogs_write8_128k_dq64_${card}_${fs}_bundle.tar.gz
        done
    done
fi

# single/multi-partitions & block device / ext4 /xfs 
if [ "${ck_multipart_rawdisk_fs}" == "1" ]; then
echo "checking multi-partitions and block device ext4 & xfs"
for card in ${multi_cards[@]};
do
    disk_csd=/dev/${card}
    sudo umount ${disk_csd}
    mount_point=${mount_dir}/${card}
    sudo umount ${mount_point}
    echo y | sudo sfx-nvme format ${disk_csd} -s 1
    parted_drv ${disk_csd} ${partitions}
    sudo ${sfx_logs} > ${log_dir}/sfxlogs_multi_part_${card}.out  2>&1
    sudo mv output*.tar.gz ${log_dir}/sfxlogs_multi_part_${card}.tar.gz

    for fs in ${fs_types};
    do
        for i in $(seq 1 ${partitions});
        do
            # run fio on multi-partition block device
            sudo tool/fio --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --name=init_randwrite_${card}p${i} --rw=randwrite --bs=4k --iodepth=32 --runtime=${fio_runtime} --filename=${disk_csd}p${i} --output=${log_dir}/init_randwrite_4k_dq32_${card}p${i}.log
            sudo ${sfx_logs} > ${log_dir}/sfxlogs_rawdisk_randw_${card}p${i}.out  2>&1
            sudo mv *_bundle.tar.gz ${log_dir}/sfxlogs_rawdisk_${card}p${i}_${fs}_bundle.tar.gz

            mount_part_point=${mount_dir}/${card}p${i}
            sudo umount ${mount_part_point}
            if [ "${fs}" == "xfs" ]; then
                sudo mkfs -t ${fs} -f ${disk_csd}p${i}
            else
                sudo mkfs -t ${fs} ${disk_csd}p${i}
            fi
            if [ ! -d ${mount_part_point} ]; then
               mkdir -p ${mount_part_point}
            fi
            sudo mount ${disk_csd}p${i} ${mnt_opt} ${mount_part_point}
            sudo tool/fio --ioengine=libaio --randrepeat=0 --norandommap --thread --direct=1 --group_reporting --time_based  --random_generator=tausworthe --runtime=${fio_runtime} --output=${log_dir}/write_128k_dq64_${card}p${i}_${fs}.log --directory=${mount_part_point} --size=30000M --bs=128k --name=ext4_write8_throughput_${card}p${i}_${fs} --rw=write --numjobs=8 --iodepth=64
            sudo ${sfx_logs} > ${log_dir}/sfxlogs_write_128k_dq64_${card}p${i}_${fs}.out  2>&1
            sudo mv *_bundle.tar.gz ${log_dir}/sfxlogs_write_128k_dq64_${card}p${i}_${fs}_bundle.tar.gz
            sleep 5
            sudo umount ${disk_csd}p${i}
        done
    done
done
fi

# gets logs with 512 bytes sector
if [ "${ck_512B_sector}" == "1" ]; then
echo "checking 512 bytes sector"
for card in ${multi_cards[@]};
do
    disk_csd=/dev/${card}
    sudo umount ${disk_csd}
    echo y | sudo sfx-nvme format ${disk_csd} -l 0
    sudo ${sfx_logs} > ${log_dir}/sfxlogs_512sector_${card}.out  2>&1
    sudo mv *_bundle.tar.gz ${log_dir}/sfxlogs_512sector_${card}_bundle.tar.gz
done
fi

# gets logs with 4096 bytes sector
if [ "${ck_4K_sector}" == "1" ]; then
echo "checking 4k sectors"
for card in ${multi_cards[@]};
do
    disk_csd=/dev/${card}
    sudo umount ${disk_csd}
    echo y | sudo sfx-nvme format ${disk_csd} -l 1
    sudo ${sfx_logs} > ${log_dir}/sfxlogs_4k_${card}.out  2>&1
    sudo mv *_bundle.tar.gz ${log_dir}/sfxlogs_4k_${card}_bundle.tar.gz
done
fi

# gets logs with atomic write enabled or disabled 
if [ "${ck_aw_onoff}" == "1" ]; then
    echo "checking aw off and on"
    for card in ${multi_cards[@]};
    do  
    disk_csd=/dev/${card}
    sudo umount ${disk_csd}
    echo y | sudo sfx-nvme format ${disk_csd} -l 1
    sudo sfx-nvme sfx set-feature /dev/sfdv0n1 -f 1 -v 1
    sudo sfx-status  |grep Atomic
    sudo ${sfx_logs} > ${log_dir}/sfxlogs_awon_${card}.out  2>&1
    sudo mv *_bundle.tar.gz ${log_dir}/sfxlogs_awon_${card}_bundle.tar.gz

    sudo sfx-nvme sfx set-feature /dev/sfdv0n1 -f 1 -v 0
    sudo sfx-status  |grep Atomic
    sudo ${sfx_logs} > ${log_dir}/sfxlogs_awoff_${card}.out  2>&1
    sudo mv *_bundle.tar.gz ${log_dir}/sfxlogs_awoff_${card}_bundle.tar.gz
    done
fi

# gold image
if [ "${ck_gold_image}" == "1" ]; then
echo "doing gold image"
${bin_bash} remote-ufpgd.sh
 
# get remote bundle-log path 
${gdssh_cmd} scp tcn@${goldimage_server}:${gdimg_case_dir}/log_dir.out ${log_dir}
gd_log_dir=`cat ${log_dir}/log_dir.out`
echo "gd_log_dir=${gd_log_dir} "

sleep ${wait_gdimage_upgrade}
echo "start powercycle"
remote_powerCycle ${goldimage_server}
echo "check gold image sfx-logs"
ssh ${goldimage_server} "${bin_bash} ${gdimg_case_dir}/cgdimage-logs.sh ${gd_log_dir}"
echo "copying remote bundle_logs: scp -r tcn@${goldimage_server}:${gd_log_dir} ${log_dir} "
${gdssh_cmd} scp -r tcn@${goldimage_server}:${gd_log_dir} ${log_dir}/
fi
