#!/usr/bin/ash

panic() {
	echo "$@" >&2
	exit 1
}

# Scan a partition $1 for type $2 and set result
# $2 must be in the format 'TYPE=query', for example 'LABEL=kupfer_boot'
check_partition_type()
{
	unset RESULT
	local partition="$1"
	local query="$2"

	busybox partprobe "$partition" 2>/dev/null || true

	if ( blkid "$partition" -t "$query" ); then
		echo "check_partition_type found $query at: $partition"
		export RESULT="$partition"
		return 0
	fi
	return 1
}

# Function will search for an available loopdev and export $LOOPDEV as a result after setup
# $1 = Partition to scan
setup_loopdev()
{
	local partition="$1"

	# Get sector size from deviceinfo
	eval "$(cat /etc/kupfer/deviceinfo)"
	deviceinfo_rootfs_image_sector_size="${deviceinfo_rootfs_image_sector_size:-512}"

	local _loopdev="$(losetup -f)"
	losetup -P -b "$deviceinfo_rootfs_image_sector_size" "$_loopdev" "$partition"
	busybox partprobe "$_loopdev"

	if [ -n "$(ls "${_loopdev}"p?*)" ]; then
		export LOOPDEV="$_loopdev"
		return 0
	else
		echo "loopdev $_loopdev for $partition didn't show any subpartitions"
		losetup -d "$_loopdev"
		return 1
	fi
}

# Probe partitions inside of a partition
subpartition_probe()
{
	local partition="$1"
	local query="$2"

	setup_loopdev "$partition" || return 1

	# Scan all subpartitions
	for subpart in "$LOOPDEV"p?*; do
		! check_partition_type "$subpart" "$query" || return 0
	done

	return 1
}


# Arguments:
	# $1 = Partition to scan
	# $2 = grep $2 from blkid

# $2 must be in the format 'TYPE=query', for example 'LABEL=kupfer_boot'
scan_partitions()
{
	local partition="$1"
	local query="$2"

	echo "scanning $partition for $query"
	# Probe partition directly first
	! check_partition_type "$partition" "$query" || return 0

	# Then scan for subpartitions
	part_table_type="$(blkid -p -s PTTYPE -o value -n dos,gpt "$partition")"
	if [ "$part_table_type" = "gpt" ] || [ "$part_table_type" = "dos" ]; then
		echo "Found partition table ($part_table_type) at: $partition"
		! subpartition_probe "$partition" "$query" || return 0
	fi

	return 1
}
