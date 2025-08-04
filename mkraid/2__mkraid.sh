#!/bin/bash
set -e

DEVLIST_FILE="__raid_disks.txt"
MOUNTPOINT="/localdisk"
RAID_DEVICE="/dev/md0"

# ✅ Check for disk list file
if [ ! -s "$DEVLIST_FILE" ]; then
    echo "❌ Device list file '$DEVLIST_FILE' is missing or empty."
    exit 1
fi

# ✅ Read devices
mapfile -t DEVICES < "$DEVLIST_FILE"
echo "🛠️ Using ${#DEVICES[@]} devices:"
printf ' - %s\n' "${DEVICES[@]}"

# ✅ Install mdadm
sudo apt update
sudo apt install -y mdadm

# ✅ Wipe existing metadata
echo "🧹 Zeroing superblocks on member disks..."
for dev in "${DEVICES[@]}"; do
    sudo mdadm --stop "$RAID_DEVICE" || true
    sudo umount "$dev" || true
    sudo wipefs -a "$dev" || true
    sudo mdadm --zero-superblock --force "$dev" || true
done

# ✅ Create RAID 0
echo "⚙️ Creating RAID 0..."
sudo mdadm --create --verbose "$RAID_DEVICE" --level=0 --raid-devices=${#DEVICES[@]} "${DEVICES[@]}"

# ✅ Wait and format
sleep 5
echo "📦 Formatting RAID with ext4..."
sudo mkfs.ext4 -F "$RAID_DEVICE"

# ✅ Mount
echo "📁 Mounting RAID at $MOUNTPOINT..."
sudo mkdir -p "$MOUNTPOINT"
sudo mount "$RAID_DEVICE" "$MOUNTPOINT"

# ✅ Persist RAID config
echo "💾 Updating mdadm.conf and initramfs..."
sudo sed -i '/ARRAY \/dev\/md0/d' /etc/mdadm/mdadm.conf
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf > /dev/null
sudo update-initramfs -u

# ✅ Persist mount with UUID
echo "📌 Persisting mount in /etc/fstab..."
RAID_UUID=$(sudo blkid -s UUID -o value "$RAID_DEVICE")
grep -q "$RAID_UUID" /etc/fstab || echo "UUID=$RAID_UUID $MOUNTPOINT ext4 defaults,nofail,discard 0 0" | sudo tee -a /etc/fstab > /dev/null

echo "✅ RAID 0 created, mounted at $MOUNTPOINT, and will persist after reboot."
