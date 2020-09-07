#!/bin/bash

# gold image
bin_bash=${bin_bash-/bin/bash}
gdimg_case_dir=${gdimg_case_dir-/tmp/goldimage-case}
pushd ${gdimg_case_dir} 
${bin_bash} gd-case.sh > ${gdimg_case_dir}/gd-case.out 2>&1

for i in {1..12000};
do
    grep "install succeed" ${gdimg_case_dir}/gd-case.out
    if [ $? -eq 0 ]; then
       echo "driver installation finished"
       break
    fi
    sleep 1
done

cat ${gdimg_case_dir}/log_dir.out
log_dir=`cat ${gdimg_case_dir}/log_dir.out`
echo "log_dir=${log_dir} " 	

# upgrade image
echo "sudo sfx-fwdownload -a ${fpga_base_dir}/${fpga_version}/" > ${log_dir}/fwdownload.out
sudo sfx-fwdownload -a ${fpga_base_dir}/${fpga_version}/ >> ${log_dir}/fwdownload.out 2>&1 &

sleep 1

for i in {1..12000};
do
    if [ -e ${log_dir}/fwdownload.out ]; then
       echo "starts upgrade image...."
       break
    fi
    echo "checking ${log_dir}/fwdownload.out existing ?...."
    sleep 1
done

