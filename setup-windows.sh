#!/bin/bash

# (Re)Download VirtIO Driver ISO (to get the latest version)
echo "Downloading VirtIO Driver ISO..."
rm -f virtio-win-latest.iso
curl -L -o virtio-win-latest.iso https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso

echo "Copying UEFI Variables File..."
rm -f OVMF_VARS.4m.fd
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd OVMF_VARS.4m.fd

# If we are on BTRFS we need to use the nodatacow option when creating the image
# See https://wiki.archlinux.org/title/QEMU#Creating_new_virtualized_system
# TODO: Extend this check for other Copy-On-Write filesystems
# Since there is no way to disable compression in the qcow2 format, we might as well use a newer algorithm than the default (zlib)
echo "Creating Disk Image..."
if [ "$(stat -f -c %T .)" = "btrfs" ]; then
  qemu-img create -f qcow2 -o compression_type=zstd,nocow=on DriveC.qcow2 128G
else
  qemu-img create -f qcow2 -o compression_type=zstd DriveC.qcow2 128G
fi

# If there is an unattend.iso, mount it when starting the VM for OS install
unattend_iso=""
if [ -f unattend.iso ]; then
  unattend_iso="-drive file=unattend.iso,media=cdrom "
fi

# Try to figure out what ISO to use
if [ -z "$1" ]; then
  # No Argument was supplied, try to find an ISO laying around
  count=$(find . -maxdepth 1 -type f -name "*.iso" ! -name "unattend.iso" ! -name "virtio-win-latest.iso" | wc -l)
  
  if [ "$count" -gt 1 ]; then
    echo "Unable to figure out which ISO to mount for the OS install. Please manually pass it as the first argument"
  else
    # Only one ISO laying around, must be the OS one, use it
    file=$(find . -maxdepth 1 -type f -name "*.iso" ! -name "unattend.iso" ! -name "virtio-win-latest.iso")
    file=${file/.\//""} # Replace the ./ prefix on the file name just to make sure
    install_iso="-drive file=$file,media=cdrom "
  fi
else
  # An ISO was supplied, use it
  install_iso="-drive file=$1,media=cdrom "
fi

echo "Using '$file' as the OS install ISO..."

# Check if a keymap for VNC was supplied
if [ -z "$2" ]; then
  # No keymap was supplied, guess it from system config
  # TODO: Maybe figure out error handling for when the system is not running SystemD
  keymap=$(localectl status | grep 'VC Keymap' | awk '{print $3}')
  length=${#keymap}

  # If the keymap is not 2 characters long, it might be empty or something like 'da-latin1', which i dont know if it will work
  if [ "$length" -eq 2 ]; then
    echo "No keymap supplied as the second argument, using '$keymap'"
  else
    echo "No keymap supplied as the second argument, exiting because the system-provided keymap ('$keymap') does not look right"
    exit 1
  fi
else
  keymap=$2
fi

echo "Starting VM for install..."

# Start the Virtual Machine
# Because Windows has not been installed yet, we enable VNC and do not need port forwarding for RDP
qemu-system-x86_64 \
-machine q35 \
-cpu host \
-enable-kvm \
-smp 8 \
-m 8G \
-drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
-drive if=pflash,format=raw,file=OVMF_VARS.4m.fd \
-drive file=DriveC.qcow2,if=virtio,cache=writeback \
-drive file=virtio-win-latest.iso,media=cdrom \
$install_iso \
$unattend_iso \
-netdev user,id=net0 \
-device virtio-net-pci,netdev=net0 \
-device virtio-balloon \
-device virtio-rng-pci \
-device virtio-scsi-pci \
-usb \
-device usb-tablet \
-k $keymap \
-display none \
-vnc :0
