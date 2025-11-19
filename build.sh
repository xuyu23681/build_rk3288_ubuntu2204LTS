#!/bin/bash
set -e

DISTRO=${1:-jammy}        # 默认 jammy=22.04，传 focal=20.04 也行
ROOTFS_SIZE=4096          # 4GB rootfs，可改大
CORES=$(nproc)

echo "========== Firefly-RK3288 Ubuntu $DISTRO 一键编译开始 =========="

# 1. 创建工作目录
mkdir -p work/rootfs work/rockdev

# 2. 用 debootstrap 构建干净 Ubuntu 22.04 armhf RootFS
echo ">>> 正在创建 Ubuntu $DISTRO armhf RootFS..."
sudo rm -rf work/rootfs
sudo debootstrap --arch=armhf --foreign $DISTRO work/rootfs http://ports.ubuntu.com/ubuntu-ports/

sudo cp /usr/bin/qemu-arm-static work/rootfs/usr/bin/
sudo chroot work/rootfs /debootstrap/debootstrap --second-stage

# 3. 基础配置 + 安装常用包
cat << EOF | sudo chroot work/rootfs
export DEBIAN_FRONTEND=noninteractive
echo "nameserver 8.8.8.8" > /etc/resolv.conf
apt update
apt install -y sudo network-manager openssh-server wpasupplicant \
               ubuntu-minimal ubuntu-desktop-minimal \
               linux-firmware firmware-realtek mesa-utils curl wget
# 创建默认用户 firefly
useradd -m -s /bin/bash firefly
echo firefly:firefly | chpasswd
usermod -aG sudo,adm firefly
echo "firefly ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
EOF

# 4. 生成 rootfs.img
echo ">>> 生成 rootfs.img..."
sudo genext2fs -b $((ROOTFS_SIZE*256)) -d work/rootfs/ work/rockdev/rootfs.img
sudo tune2fs -L rootfs work/rockdev/rootfs.img

# 5. 使用官方最稳 U-Boot（直接拷贝，不编译！）
cp u-boot-official/idbloader.img work/rockdev/
cp u-boot-official/u-boot.itb     work/rockdev/
cp u-boot-official/trust.img      work/rockdev/

# 6. 使用 rkbin 官方工具生成完整镜像
echo ">>> 打包完整镜像..."
cd work/rockdev
ln -sf ../../rkbin .

# 生成 parameter.txt（GPT 分区，兼容 eMMC/SD）
cat > parameter.txt <<EOF
FIRMWARE_VER: 1.0
MACHINE_MODEL: Firefly-RK3288
MACHINE_ID: 007
MANUFACTURER: Firefly
MAGIC: 0x5041524B
ATAG: 0x00200800
MACHINE: 3288
CHECK_MASK: 0x80
PWR_HLD: 0,0,A,0,1
#CMDLINE: console=ttyS2,115200n8 root=/dev/mmcblk0p2 rootwait ro
CMDLINE: console=ttyS2,115200n8 root=LABEL=rootfs rootwait rw
EOF

# 使用官方工具打包
../../rkbin/tools/mkimage.sh

# 输出最终镜像
cp Image*.img ../../output/Firefly-RK3288-Ubuntu22.04-$(date +%Y%m%d)-official-uboot.img

echo "============================================================"
echo "编译完成！镜像在 output/ 目录："
ls -lh ../../output/*.img
echo "直接用 Etcher 或 dd 烧录到 SD 卡 / eMMC 即可使用"
echo "默认用户：firefly / firefly"
echo "享受你的 Ubuntu 22.04 + 最稳官方 U-Boot 组合吧！"
