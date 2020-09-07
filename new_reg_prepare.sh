#!/bin/bash

# Copyright 2017 ScaleFlux, Inc.

# Usage ./regression_prepare.sh -h | --kc|--pl|--rh|--sfxrpm| --rpm [ [REVISION] [--br BRANCH ] [--kn KERNEL] [--old [--lvl OLDER_LEVEL]] ] [--sbs BLOCK_SIZE] [--ms MULTIPLE_STREAM_STATUS] [--aw ATOMIC_WRITE_STATUS]| --all

dest_path=$(cd `dirname $0`; pwd)
kernel=0
prebuilt=0
runhalfKB=0
use_branch=0
use_kernel=0
use_path=0
use_older=0
installrpm=0
mutiple_stream=0
atomic_wr=0
level=2
rev="auto"
sfxinstallrpm=0
multiple_stream=0
kerver=`uname -r | awk -F '.' '{print $1"."$2}'`
ubuntu=0
ker=`uname -a`
set_blocksize=0
package_name=sfx_qual_suite.tar.gz
regtool_name=sfx_qual_suite
new_build_tree=0
daily_build_path="/share/releases/Daily"
clean_card=0
capacity_set=0
yum_install=0
src_pkg=0
sfx_mformat=0
src_install=0
dynamic_capacity_set=0
p_capacity_set=0

if [[ $ker == *"Ubuntu"* ]]; then
        ubuntu=1
fi
if [ $kerver = "4.1" ]; then
        osdist=`cat /etc/redhat-release | egrep -o "[0-9]" | head -1`
        kerver=${kerver}_centos$osdist
fi

# For Ubuntu
uname -a | grep -i Ubuntu
if [ $? -eq 0 ]; then
	kerver=`uname -r | awk -F '-' '{print $1"-"$2}'`_ubuntu
fi

#check cards num on testing machine
n=`lspci -d cc53: | sed -n '$='`

usage() {
	echo "./regression_prepare.sh -h | --kc|--pl|--rh|--rpm | [--br BRANCH ] [--kn KERNEL] [--old [--lvl OLDER_LEVEL]] [--ms] [--sbs test_blocksize] [--aw] [--cl] [--dest DEST_PATH] [--pk PACKAGE_NAME]] [--capacity capacity_num] [--dynamic_capacity capacity_num] [--p_capacity capacity_num] [--yum] [--src_pkg]| --mformat| [--src_install] --all"
	echo "Default if have --br branch_name, will find the latest daily build to install except with --pth"
	printf "%-35s%-35s\n" "--br BRANCH"  "##branch name"
	printf "%-35s%-35s\n" "--pth BUILD_PATH" "##specified build path"
	printf "%-35s%-35s\n" "--kn KERNEL"  "##kernel, if not use --kn, will automatically to find"
	printf "%-35s%-35s\n" "--rpm" "##will use rpm --ivh to install build, for ubuntu, use dpkg -i"
	printf "%-35s%-35s\n" "--yum" "##will use yum to install build, for ubuntu, use dpkg -i"
	printf "%-35s%-35s\n" "--sbs BLOCK_SIZE" "##will use sfx_nvme format –ses=0 –lbaf=0(512)|1(4096)  /dev/sfd*"
	printf "%-35s%-35s\n" "--aw" "##enable atomic write, also change sector size to 4096"
	printf "%-35s%-35s\n" "--cl" "##do initcard.sh --cl to clean card before install build"
	printf "%-35s%-35s\n" "--mformat" "##do sfx-nvme sfx set-feature -f 0xdc /dev/sfxv0 --force to format all cards"
	printf "%-35s%-35s\n" "--src_intall" "##will use src_install.sh to install build, if no kernel rpm, will use souce rpm"
	printf "%-35s%-35s\n" "--dynamic_capacity" "will use sfx-nvme sfx change-cap to modify capacity"
	printf "%-35s%-35s\n" "--capacity" "use sfx-nvme sfx format -c to change capacity"
	printf "%-35s%-35s\n" "--p_capacity" "use sfx-nvme sfx set-feature -f 0xac -v capacity_num --force to change p_capacity"
	exit 0
}

while [ $# -gt 0 ]
do
	case $1 in
		-h|--help) usage ;;
		--kc)  kernel=1 ;;
		--pl)  prebuilt=1 ;;
		--rh)  runhalfKB=1 ;;
		--old) use_older=1 ;;
		--lvl) level=$2; shift ;;
		--br)  use_branch=1; branch_name=$2; shift ;;
		--kn)  use_kernel=1; kernel_name=$2; shift ;;
		--pth) use_path=1 ; rpm_path=$2; shift ;;
		--rpm) installrpm=1;; #using rpm -ivh to install build
		--all) kernel=1; prebuilt=1; runhalfKB=1 ;;
		--sfxrpm) sfxinstallrpm=1;;
		--sbs) set_blocksize=1; test_blocksize=$2; shift ;;
		--dest) dest_path=$2;;
		--pk) package_name=$2;;
		--ms) multiple_stream=1;; #enable multiple stream
		--aw) atomic_wr=1;; #enable atomic wr option
		--cl) clean_card=1;; #will -s install build then do sfx-mformat
		--capacity) capacity_set=1; capacity_num=$2; shift ;; #change capacity for card
		--yum) yum_install=1;; #using yum install build, for ubuntu use dpkg
		--src_pkg) src_pkg=1;; #if --src_pkg will copy src_pkg otherwise not copy src_pkg and generic package
		--mformat) sfx_mformat=1;; # will use sfx-nvme sfx set-feature -f 0xdc /dev/sfxv0 --force
		--src_install) src_install=1;; # will use src package to install build, for souce rpm
		--dynamic_capacity) dynamic_capacity_set=1; dynamic_capacity_num=$2; shift;;
		--p_capacity) p_capacity_set=1; p_capacity_num=$2; shift;;
	esac
	shift
done

function get_device(){
    check_sfx=`ls /dev | grep sfxv`
    if [[ $check_sfx != "" ]]; then
        sfx_devices=`ls -v /dev/sfxv[0-9]*`
        sfx_num=`ls /dev/sfxv[0-9]* | sed -n '$='`
    fi
    check_sfd=`ls /dev | grep sfdv`
    if [[ $check_sfd != "" ]]; then
        sfd_devices=`ls -v /dev/sfdv[0-9]*n1`
        sfd_num=`ls /dev/sfdv[0-9]*n1 | sed -n '$='`
    fi
    n=`lspci -d cc53: | sed -n '$='`
}

# find branch name
if [ $use_branch -eq 1 ]; then
	branch=$branch_name
else
	output=`svn info 2>&1`
	if [ $? -eq 0 ]; then
		branch=`svn info | grep '^URL:' | egrep -o 'branches/[^/]+|trunk' | egrep -o '[^/]+$'`
	fi
fi


# run kernel_check script
if [ $kernel -eq 1 ]; then
	DEFAULT_KERNEL="2.6 4.1_centos6"
	testkerver=`echo $DEFAULT_KERNEL|grep $kerver`
	files_dir="$sw_path/applications/triphora_test/src"
	checkModify=`cat  $files_dir/sfx_run_copy.py |sed -n 1p | grep "python2.7"`
	if test "$testkerver" != ""; then
		if test "$checkModify" = ""; then
			sed -ie 's/bin.*python/local\/bin\/python2.7/g' $files_dir/sfx_run_copy.py $files_dir/sfx_run_pattern.py $ccs_dir/ccsreg.py
			sed -ie 's/bin/local\/bin/g' $ruby_dir/sfx-run-benchmark.rb
		fi
	fi
fi


function driver_unload(){
	for driver in "sfxv_bd_dev" "sfvv" "sfxvdriver"
	do
		output=`lsmod | grep $driver`
		if [[ $output != "" ]]; then
			sudo modprobe -r $driver
			if [[ $? -ne 0 ]]; then
				echo "ERROR: failed to remove $driver"
				exit 1
			else
				echo "SUCCESSFULL: removed $driver"
			fi
		fi
	done
}

# find os name based on kernel version
if [ $use_kernel -eq 1 ]; then
	ker=$kernel_name;
else
	ker=`uname -r`
fi
case $ker in
	3.10.0-327 | 3.10.0-327.el7.x86_64) os="centos7.2" ;;
	3.10.0-514.21.1.el7_lustre) os="lustre-7.3" ;;
	3.10.0-514 | 3.10.0-514.el7.x86_64) os="centos7.3" ;;
	3.10.0-693 | 3.10.0-693.el7.x86_64) os="centos7.4" ;;
	4.1.0-13)   os="ucloud4.x-centos7.2" ;;
	4.1.0-17)   os="ucloud4.x-centos7.2" ;;
	4.1.0-19)   os="ucloud4.x-centos7.2" ;;
	4.14.0-5)   os="ucloud4.x-centos7.2" ;;
	2.6.32-642 | 2.6.32-642.el6.x86_64) os="centos6.8" ;;
	4.1.0-13.el6)   os="ucloud4.x-centos6.3" ;;
	4.1.0-17.el6)   os="ucloud4.x-centos6.3" ;;
	4.1.0-19.el6)   os="ucloud4.x-centos6.3" ;;
        2.6.32-573 | 2.6.32-573.el6.x86_64) os="centos6.7" ;;
	2.6.32-696 | 2.6.32-696.el6.x86_64) os="centos6.9" ;;
	2.6.32-642 | 2.6.32-642.el6.x86_64) os="centos6.8" ;;
	2.6.32-431 | 2.6.32-431.el6.x86_64) os="centos6.5" ;;
	2.6.32-504 | 2.6.32-504.el6.x86_64) os="centos6.6" ;;
	2.6.32-358 | 2.6.32-358.el6.x86_64) os="centos6.4" ;;
	2.6.32-279 | 2.6.32-279.el6.x86_64) os="centos6.3" ;;
	4.15.0-39-generic) os="ubuntu4.15.0-39" ;;
	3.16.0-30-generic) os="ubuntu3.16.0-30" ;;
	4.4.0-83-generic) os="ubuntu4.4.0-83" ;;
	4.4.0-103-generic) os="ubuntu4.4.0-103" ;;
	4.13.0-37-generic) os="ubuntu4.13.0-37" ;;
        4.4.0-119-generic) os="ubuntu4.4.0-119" ;;
        4.4.0-127-generic) os="ubuntu4.4.0-127" ;;
	4.4.0-133-generic) os="ubuntu4.4.0-133" ;;
	4.4.0-134-generic) os="ubuntu4.4.0-134" ;;
        4.4.0-137-generic) os="ubuntu4.4.0-137" ;;
	4.4.0-138-generic) os="ubuntu4.4.0-138" ;;
	4.4.0-139-generic) os="ubuntu4.4.0-139" ;;
	4.4.0-142-generic) os="ubuntu4.4.0-142" ;;
	4.8.0-34-generic) os="ubuntu4.8.0-34";;
	4.9.75) os="centos7-4.9.75" ;;
        3.10.0-862 | 3.10.0-862.el7.x86_64) os="centos7.5" ;;
	4.9.0-6-amd64) os="debian4.9.0-6" ;;
        3.19.0-28-generic) os="ubuntu3.19.0-28" ;;
	3.10.0-957 | 3.10.0-957.el7.x86_64) os="centos7.6" ;;
        3.10.0-327.ali2013 | 3.10.0-327.ali2013.alios7.x86_64 | 3.10.0-327.ali2013.alios7) os="alios7" ;;
	4.18.0-80.11.2.el8_0.x86_64 | 4.18.0-80.11.2.el8_0 | 4.18.0-80) os="centos8.0" ;;
esac

#check os is blank
if [[ $os == "" ]]; then
	if [[ $ubuntu -eq 1 ]]; then
		os=`echo $ker | sed 's/-generic//g'`
		os="ubuntu"$os
	else
		echo "ERROR: NOT found the corresponding OS"
		echo "input or get kernel is $ker"
		exit 1
	fi
fi

# use older rpm
if [ $use_older -eq 1 ]; then
	count=`ls $daily_build_path/ | wc -l`
	for ((i=1; i < `expr $count + 1`; i++)); do
		dating=`ls $daily_build_path/ | sort -r | sed -n ${i}p`
		number=`ls $daily_build_path/$dating/$branch/$os | wc -l`
		if [ $number -ge $level ]; then
			rev=`ls $daily_build_path/$dating/$branch/$os | sort -r | sed -n ${level}p`
			break
		else
			level=`expr $level - $number`
		fi
	done
fi
if [ $use_path -eq 1 ]; then
    dir=$rpm_path
    echo $dir|grep /$
    if [ $? = 0 ];then
        dir=${dir%?}
    fi
    revision=`echo $dir|awk -F "/" '{print $NF}'`
    if [ ! -d $dir ]; then
        echo "Cannot find rpm path $rpm_path"
        exit 1
    fi
    if [ -d $dir/bin_pkg ]; then
	new_build_tree=1
    fi
else
    #count=`ls $daily_build_path/ | wc -l`
    for ((i=1; i < 10; i++)); do
        dating=`ls $daily_build_path/ | sort -r | sed -n ${i}p`
	#check it is new build tree or old
	if [[ -d $daily_build_path/$dating/$branch/$os ]]; then
                revision=`ls $daily_build_path/$dating/$branch/$os | sort -r |sed -n 1p`
        fi
        dir="$daily_build_path/$dating/$branch/$os/$revision"
        if [ -d $dir ]; then
                break
	else
		rev_count=`ls $daily_build_path/$dating/$branch | wc -l`
		for ((j=1; j < `expr $rev_count + 1`; j++)); do
			revision=`ls $daily_build_path/$dating/$branch | sort -r |sed -n ${j}p`
			dir="$daily_build_path/$dating/$branch/$revision"
			if [ -e $dir/bin_pkg/$os ]; then
				new_build_tree=1
				break
			fi
		done
		if [ $new_build_tree -eq 1 ]; then
			break #find the kernel build and it is also new build folder structure
		fi
        fi
    done
fi

echo "Found build ${dir}, prepare to copy build, please wait..."

if [ -f revision_num ]; then
        checkoldrev=`cat revision_num`
	if [[ $checkoldrev != "" ]]; then
		if [ -d $dest_path/$checkoldrev ]; then
			sudo rm -rf $dest_path/$checkoldrev #remove old build package
		fi
		sudo chmod 777 revision_num
	fi
fi

currentuser=`who am i | awk '{print $1}' `

if [ $new_build_tree -eq 0 ]; then
	cp -rf $dir $dest_path
	tar -xzf $dest_path/$revision/$package_name -C $dest_path
else
	#if using new build tree
	mkdir -p $dest_path/$revision
	mkdir -p $dest_path/$revision/bin_pkg
	cp -rf $dir/bin_pkg/$os $dest_path/$revision/bin_pkg
	if [[ $src_pkg -eq 1 ]] || [[ $src_install -eq 1 ]]; then
		cp -rf $dir/bin_pkg/generic* $dest_path/$revision/bin_pkg
		cp -rf $dir/src_pkg $dest_path/$revision
		cp -rf $dir/*.src.* $dest_path/$revision
	fi
	cp -rf $dir/sfxinstall.sh $dir/sfx_install_package.sh $dest_path/$revision
	tar -xzf $dest_path/$revision/bin_pkg/$os/$package_name -C $dest_path
fi

echo "Found and copied build from ${dir}"

echo $revision > revision_num
sudo chmod 777 revision_num
sudo chown -R $currentuser:root $dest_path/$regtool_name

if [ $kernel -eq 1 ]; then
        DEFAULT_KERNEL="2.6 4.1_centos6"
        testkerver=`echo $DEFAULT_KERNEL|grep $kerver`
        files_dir="$dest_path/$regtool_name"
	if [ -f $files_dir/sfx_run_copy ];then
		checkModify=`cat  $files_dir/sfx_run_copy |sed -n 1p | grep "python2.7"`
	fi
        if test "$testkerver" != ""; then
		py_file="$files_dir/sfx_run_copy $files_dir/sfx_run_pattern $files_dir/ccsreg"
                if test "$checkModify" = ""; then
			for file in $py_file
			do
				if [ -f $file ];then
					sed -ie 's/bin.*python/local\/bin\/python2.7/g' $file
				fi
			done
			sed -ie 's/bin/local\/bin/g' $files_dir/sfx-run-benchmark.rb
			sed -ie 's/bin/local\/bin/g' $files_dir/sfx_run_benchmark
		fi
        fi
fi

if [[ $yum_install -eq 1 ]] || [[ $installrpm -eq 1 ]] || [[ $src_install -eq 1 ]]; then
	# find the latest rpm pkg
        dir=$dest_path/$revision
	sfxparam_path="/etc/scaleflux/sfxparam"

	# install new rpm
        cd $dir/bin_pkg/$os
        if [ $ubuntu -eq 1 ]; then
                check_build=`dpkg -l |grep -E "sfxvdriver|sfx3xdriver" | awk '{print $2}'`
        else
                check_build=`rpm -qa|grep -E "sfxv_bd_dev|sfx3xdriver"`
        fi

	if [[ $clean_card -eq 1 ]]; then #if need to clean card before testing, unload driver then install driver
		driver_unload

	#uninstall build if already has build on testing machine
	if [[ $check_build != "" ]]; then
		if [ $ubuntu -eq 1 ]; then
			sudo apt-get -y remove $check_build --purge
		else
			sudo rpm -e $check_build
		fi
		if [[ $? -ne 0 ]]; then
			echo "ERROR: uninstall build failed"
			exit 1
		else
			echo "Removed old build"
			echo ""
		fi
	fi
		cd $dir/../$regtool_name
		echo "###"
		echo "using initcard --cl to clean card"
		sudo ./initcard.sh --cl
		if [[ $? -ne 0 ]]; then
			echo "clean card failed"
			exit 1
		else
			echo "###"
			echo "clean card successful"
			echo ""
		fi
		sudo rmmod sfxvdriver
	fi
	if [[ $src_install -eq 0 ]]; then
	cd $dir/bin_pkg/$os
	build_name=`ls | grep -E "sfxv_bd_dev|sfx3xdriver"`
	if [[ $ubuntu -eq 1 ]]; then
		sudo dpkg -i $build_name
	else
		if  [[ $yum_install -eq 0 ]]; then
			if [[ $os =~ "alios" ]]; then
				sudo rpm -Uvh --nodeps --force $build_name
			else
				sudo rpm -Uvh --force $build_name
			fi
		else
			if [[ $clean_card -eq 1 ]] || [[ $check_build == "" ]]; then
				sudo yum install -y $build_name
			else
				sudo yum upgrade -y $build_name
			fi
		fi
	fi
	if [ $? -ne 0 ]; then
		echo "FAIL TO INSTALL PACKAGES"
		exit 1
	fi
	else
        if [[ $check_build != "" ]]; then
                if [ $ubuntu -eq 1 ]; then
                        sudo apt-get -y remove $check_build --purge
                else
                        sudo rpm -e $check_build
                fi
                if [[ $? -ne 0 ]]; then
                echo "ERROR: uninstall build failed"
                        exit 1
                else
                        echo "Removed old build"
                        echo ""
                fi
        fi
	cd $dir
	echo "##Using src_pkg to install build"
        if [[ $ubuntu -eq 1 ]]; then
		build_name=`ls | grep -E "sfxv_bd_dev|sfx3xdriver" | grep deb`
                sudo dpkg -i $build_name
        else
		build_name=`ls | grep -E "sfxv_bd_dev|sfx3xdriver" | grep rpm`
                if [[ $os =~ "alios" ]]; then
                        sudo rpm --nodeps --force -Uvh $build_name
                else
                        sudo rpm -Uvh --nodeps $build_name
                fi
        fi
		if [ $? -ne 0 ]; then
			echo "FAIL TO INSTALL PACKAGES"
			exit 1
		fi
	fi
	if [[ $sfx_mformat -eq 1 ]]; then
		echo ""
		get_device
		for sfx_name in $sfx_devices;
		do
			card_num=`echo $sfx_name | sed 's/\/dev\/sfxv//g'`
			sfd_name="/dev/sfdv"$card_num"n1"
			echo "##using sfx-nvme sfx set-feature -f 0xdc $sfx_name --force to format card"
			sudo sfx-nvme sfx set-feature -f 0xdc $sfx_name --force
			if [[ $? -ne 0 ]]; then
				echo "`date`:ERROR:format for card $sfx_name failed"
				exit 1
			fi
		done
	fi
	if [[ $p_capacity_set -eq 1 ]]; then
		echo ""
		get_device
		for sfx_name in $sfx_devices;
		do
                        card_num=`echo $sfx_name | sed 's/\/dev\/sfxv//g'`
                        sfd_name="/dev/sfdv"$card_num"n1"
			echo "using sfx-nvme sfx set-feature -f 0xac -v $p_capacity_num $sfd_name to change p_capacity"
			sudo sfx-nvme sfx set-feature -f 0xac -v $p_capacity_num $sfd_name --force
			if [[ $? -ne 0 ]]; then
				echo "`date`:ERROR:change p_capacity failed for $sfd_name"
				exit 1
			fi
		done

	fi
        if [[ $capacity_set -eq 1 ]]; then
                get_device
                for sfx_name in $sfx_devices;
                do
                        card_num=`echo $sfx_name | sed 's/\/dev\/sfxv//g'`
                        sfd_name="/dev/sfdv"$card_num"n1"
                        echo ""
                        echo "##using sfx-nvme sfx format to change capacity for card $sfd_name to $capacity_num"
                        echo y | sudo sfx-nvme sfx format $sfd_name -c $capacity_num
                        if [[ $? -ne 0 ]]; then
                                echo "`date`:ERROR: sfx_nvme change capacity for card $sfd_name"
                                exit 1
                        fi
                done
        fi
	if [[ $dynamic_capacity_set -eq 1 ]]; then
		get_device
		for sfx_name in $sfx_devices;
		do
			card_num=`echo $sfx_name | sed 's/\/dev\/sfxv//g'`
			sfd_name="/dev/sfdv"$card_num"n1"
			echo ""
			echo "##using sfx_nvme sfx change-cap to change dynamic capacity for card $sfd_name to $dynamic_capacity_num"
			sudo sfx-nvme sfx change-cap $sfd_name -c $dynamic_capacity_num -f
			if [[ $? -ne 0 ]]; then
				echo "`date`:ERROR: sfx-nvme sfx change-cap change capacity for card $sfd_name"
				exit 1
			fi
		done
	fi

	if [[ $set_blocksize -eq 1 ]]; then
		get_device
		for sfx_name in $sfx_devices; do
		card_num=`echo $sfx_name | sed 's/\/dev\/sfxv//g'`
		sfd_name="/dev/sfdv"$card_num"n1"
		get_ss=`sudo blockdev --getss $sfd_name`
		if [[ $test_blocksize -eq 512 ]] && [[ $get_ss -eq 4096 ]]; then
			echo ""
			echo "##using sfx_nvme format to set sector size to $test_blocksize for device $sfd_name"
			echo y | sudo sfx-nvme format --ses=0 --lbaf=0 $sfd_name
			if [[ $? -ne 0 ]]; then
				echo "`date`:ERROR: sfx_nvme change sector size for card $sfd_name"
				exit 1
			fi
		fi
		if [[ $test_blocksize -eq 4096 ]] && [[ $get_ss -eq 512 ]]; then
			echo ""
			echo "##using sfx_nvme format to set sector size to $test_blocksize for device $sfd_name"
			echo y | sudo sfx-nvme format --ses=0 --lbaf=1 $sfd_name
                        if [[ $? -ne 0 ]]; then
                                echo "`date`:ERROR: sfx_nvme change sector size for card $sfd_name"
				exit 1
                        fi
		fi
		done
	fi
	if [ $atomic_wr -eq 1 ]; then
		get_device
		for sfx_name in $sfx_devices; do
                card_num=`echo $sfx_name | sed 's/\/dev\/sfxv//g'`
                sfd_name="/dev/sfdv"$card_num"n1"

		echo ""
		echo "##using sfx_nvme format to enable atomic write for device $sfd_name"
		sudo sfx-nvme sfx set-feature -f 1 -v 1 $sfd_name
		if [[ $? -ne 0 ]]; then
			echo "`date`:ERROR: sfx-nvme format change atomic write for card $sfd_name"
			exit 1
		fi
		done
	fi
	echo "Successfully installed packages: $dir"
	exit 0
fi
