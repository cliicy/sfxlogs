#!/bin/bash

sfx_logs=${sfx_logs-"/usr/bin/sfx-logs"}
gdimg_case_dir=${gdimg_case_dir-/tmp/goldimage-case}
pushd ${gdimg_case_dir} 
log_dir=$1
echo "goldimage server log_dir=${log_dir} "

# collect sfx-logs after goldimage upgrade 
sudo /usr/bin/sfx-status | grep -E "gold image|Gold Imag" > ${log_dir}/sstatus.out 2>&1
sudo ${sfx_logs} > ${log_dir}/gdimage_upgrade.out  2>&1
mv *_bundle.tar.gz ${log_dir}/bundle_gdimage.tar.gz
mv *.out ${log_dir}/
