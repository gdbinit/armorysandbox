SHELL = /bin/bash

LINUX_VER=4.9.28
UBOOT_VER=2017.05

USBARMORY_REPO=https://raw.githubusercontent.com/inversepath/usbarmory/master
TARGET_IMG=armorysandbox-debian_jessie-base_image-`date +%Y%m%d`.raw
DEBIAN_MIRROR=http://ftp.debian.org/debian/
IMAGE_SIZE=3500MiB
SSH_KEY="CHANGE_ME!"

debian:
	fallocate -l ${IMAGE_SIZE} ${TARGET_IMG}
	/sbin/parted ${TARGET_IMG} --script mklabel msdos
	/sbin/parted ${TARGET_IMG} --script mkpart primary ext4 5M 100%
	# we need to do this else mkfs will overwrite the MBR because it doesn't care about offset option
	sudo /sbin/losetup /dev/loop0 ${TARGET_IMG} -o 5242880 --sizelimit ${IMAGE_SIZE}
	sudo /sbin/mkfs.ext4 -F /dev/loop0
	sudo /sbin/losetup -d /dev/loop0
	mkdir -p rootfs
	sudo mount -o loop,offset=5242880 -t ext4 ${TARGET_IMG} rootfs/
	
	# If you need, add more packages over here
	sudo qemu-debootstrap --arch=armhf --include=ssh,sudo,ntpdate,fake-hwclock,openssl,\
	vim,nano,cryptsetup,lvm2,locales,less,cpufrequtils,isc-dhcp-server,haveged,whois,iw,\
	wpasupplicant,dbus,hfsplus,hfsprogs,hfsutils,dmg2img,gdb,gdb-arm-none-eabi,gdb-multiarch,\
	gdbserver,xz-utils,zip,curl,bzip2,gcc,gcc-arm-none-eabi,git,make,file,\
	dc3dd,extundelete,magicrescue,scalpel,shed,sleuthkit,ssdeep,yara \
	jessie rootfs ${DEBIAN_MIRROR}

	sudo cp conf/rc.local rootfs/etc/rc.local
	sudo cp conf/sources.list rootfs/etc/apt/sources.list
	# these are non-host mode related options, no need here
	#sudo cp conf/dhcpd.conf rootfs/etc/dhcp/dhcpd.conf
	#sudo sed -i -e 's/INTERFACES=""/INTERFACES="usb0"/' rootfs/etc/default/isc-dhcp-server
	echo "tmpfs /tmp tmpfs defaults 0 0" | sudo tee rootfs/etc/fstab
	echo -e "\nUseDNS no" | sudo tee -a rootfs/etc/ssh/sshd_config
	# don't leak to Google DNS if we ever set a gateway, at least by default
	#echo "nameserver 8.8.8.8" | sudo tee rootfs/etc/resolv.conf
	sudo chroot rootfs systemctl mask getty-static.service
	sudo chroot rootfs systemctl mask display-manager.service
	sudo chroot rootfs systemctl mask hwclock-save.service
	echo "ledtrig_heartbeat" | sudo tee -a rootfs/etc/modules
	echo "ci_hdrc_imx" | sudo tee -a rootfs/etc/modules
	# these are non-host mode related options, no need here
	#echo "g_ether" | sudo tee -a rootfs/etc/modules
	#echo "options g_ether use_eem=0 dev_addr=1a:55:89:a2:69:41 host_addr=1a:55:89:a2:69:42" | sudo tee -a rootfs/etc/modprobe.d/usbarmory.conf
	#echo -e 'auto usb0\nallow-hotplug usb0\niface usb0 inet static\n  address 10.0.0.1\n  netmask 255.255.255.0\n  gateway 10.0.0.2\n'| sudo tee -a rootfs/etc/network/interfaces
	echo -e 'auto eth0\nallow-hotplug eth0\niface eth0 inet static\n  address 10.1.0.1\n  netmask 255.255.255.0\n'| sudo tee -a rootfs/etc/network/interfaces
	echo "armorysandbox" | sudo tee rootfs/etc/hostname
	echo "usbarmory  ALL=(ALL) NOPASSWD: ALL" | sudo tee -a rootfs/etc/sudoers
	echo -e "127.0.1.1\tarmorysandbox" | sudo tee -a rootfs/etc/hosts
	# CHANGEME!!!!
	sudo chroot rootfs /usr/sbin/useradd -s /bin/bash -p `sudo chroot rootfs mkpasswd -m sha-512 usbarmory` -m usbarmory
	sudo mkdir rootfs/home/usbarmory/.ssh
	sudo chown 1000:1000 rootfs/home/usbarmory/.ssh
	sudo chmod 700 rootfs/home/usbarmory/.ssh
	echo ${SSH_KEY} | tee -a rootfs/home/usbarmory/.ssh/authorized_keys
	sudo chown 1000:1000 rootfs/home/usbarmory/.ssh/authorized_keys
	sudo chmod 400 rootfs/home/usbarmory/.ssh/authorized_keys
	sudo rm rootfs/etc/ssh/ssh_host_*
	sudo chroot rootfs apt-get clean
	sudo chroot rootfs fake-hwclock
	sudo rm rootfs/usr/bin/qemu-arm-static

linux-${LINUX_VER}.tar.xz:
	cp source_packages/linux-${LINUX_VER}.tar.xz .
	cp source_packages/linux-${LINUX_VER}.tar.sign .

u-boot-${UBOOT_VER}.tar.xz:
	cp source_packages/u-boot-${UBOOT_VER}.tar.bz2 .
	cp source_packages/u-boot-${UBOOT_VER}.tar.bz2.sig .

linux-${LINUX_VER}/arch/arm/boot/zImage: linux-${LINUX_VER}.tar.xz
	unxz linux-${LINUX_VER}.tar.xz
	gpg --verify linux-${LINUX_VER}.tar.sign
	tar xf linux-${LINUX_VER}.tar && cd linux-${LINUX_VER}
	#sudo cp kernel_conf/usbarmory_linux-4.9.config linux-${LINUX_VER}/.config
	sudo cp kernel_conf/armorysandbox_linux-4.9.config linux-${LINUX_VER}/.config
	sudo cp kernel_conf/imx53-usbarmory-host.dts linux-${LINUX_VER}/arch/arm/boot/dts/imx53-usbarmory-host.dts
	sudo cp kernel_conf/imx53-usbarmory-gpio.dts linux-${LINUX_VER}/arch/arm/boot/dts/imx53-usbarmory-gpio.dts
	sudo cp kernel_conf/imx53-usbarmory-spi.dts linux-${LINUX_VER}/arch/arm/boot/dts/imx53-usbarmory-spi.dts
	sudo cp kernel_conf/imx53-usbarmory-i2c.dts linux-${LINUX_VER}/arch/arm/boot/dts/imx53-usbarmory-i2c.dts
	sudo cp kernel_conf/imx53-usbarmory-scc2.dts linux-${LINUX_VER}/arch/arm/boot/dts/imx53-usbarmory-scc2.dts
	cd linux-${LINUX_VER} && KBUILD_BUILD_USER=usbarmory KBUILD_BUILD_HOST=usbarmory ARCH=arm CROSS_COMPILE=arm-none-eabi- make -j2 zImage modules imx53-usbarmory.dtb imx53-usbarmory-host.dtb imx53-usbarmory-gpio.dtb imx53-usbarmory-spi.dtb imx53-usbarmory-i2c.dtb imx53-usbarmory-scc2.dtb

u-boot-${UBOOT_VER}/u-boot.imx: u-boot-${UBOOT_VER}.tar.xz
	gpg --verify u-boot-${UBOOT_VER}.tar.bz2.sig
	tar xf u-boot-${UBOOT_VER}.tar.bz2
	cd u-boot-${UBOOT_VER} && make distclean
	cd u-boot-${UBOOT_VER} && make usbarmory_config
	cd u-boot-${UBOOT_VER} && CROSS_COMPILE=arm-none-eabi- ARCH=arm make -j2

linux: linux-${LINUX_VER}/arch/arm/boot/zImage

u-boot: u-boot-${UBOOT_VER}/u-boot.imx

finalize: u-boot-${UBOOT_VER}/u-boot.imx linux-${LINUX_VER}/arch/arm/boot/zImage
	sudo cp linux-${LINUX_VER}/arch/arm/boot/zImage rootfs/boot/
	sudo cp linux-${LINUX_VER}/arch/arm/boot/dts/imx53-usbarmory*.dtb rootfs/boot/
	# set it to host mode
	sudo cp rootfs/boot/imx53-usbarmory.dtb rootfs/boot/imx53-usbarmory.dtb-default
	sudo cp rootfs/boot/imx53-usbarmory-host.dtb rootfs/boot/imx53-usbarmory.dtb
	cd linux-${LINUX_VER} && sudo make INSTALL_MOD_PATH=../rootfs ARCH=arm modules_install
	sudo rm rootfs/lib/modules/${LINUX_VER}/build
	sudo rm rootfs/lib/modules/${LINUX_VER}/source
	sudo umount rootfs
	sudo dd if=u-boot-${UBOOT_VER}/u-boot.imx of=${TARGET_IMG} bs=512 seek=2 conv=fsync conv=notrunc
	#xz -k ${TARGET_IMG}
	#zip -j ${TARGET_IMG}.zip ${TARGET_IMG}

all: debian linux u-boot finalize

clean:
	-rm -r linux-${LINUX_VER}*
	-rm -r u-boot-${UBOOT_VER}*
	-rm armorysandbox-debian_jessie-base_image-*.raw
	-rmdir rootfs
