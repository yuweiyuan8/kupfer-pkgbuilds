#!/usr/bin/ash

panic() {
	busybox echo "$@" >&2
	exit 1
}

# Scan a partition $1 for type $2 and set result
# $2 must be in the format 'TYPE=query', for example 'LABEL=kupfer_boot'
check_partition_type()
{
	unset RESULT
	local _partition="$1"
	local _query="$2"

	busybox partprobe "$_partition" 2>/dev/null || true

	if ( blkid -p "$_partition" | grep -q "$_query" ); then
		busybox echo "check_partition_type found $_query at: $_partition"
		export RESULT="$_partition"
		return 0
	fi
	return 1
}

# Function will search for an available loopdev and export $LOOPDEV as a result after setup
# $1 = Partition to scan
setup_loopdev()
{
	local _partition="$1"

	# Get sector size from deviceinfo
	eval "$(cat /etc/kupfer/deviceinfo)"
	deviceinfo_rootfs_image_sector_size="${deviceinfo_rootfs_image_sector_size:-512}"

	local _loopdev="$(losetup -f)"
	losetup -P -b "$deviceinfo_rootfs_image_sector_size" "$_loopdev" "$_partition"
	busybox partprobe "$_loopdev"

	if [ -e ${_loopdev}p?* ]; then
		export LOOPDEV="$_loopdev"
		return 0
	else
		losetup -d "$_loopdev"
		return 1
	fi
}

# Probe partitions inside of a partition
subpartition_probe()
{
	local _partition="$1"
	local _query="$2"

	setup_loopdev "$_partition" || return 1

	# Scan all subpartitions
	for subpart in "$LOOPDEV"p?*; do
		! check_partition_type "$subpart" "$_query" || return 0
	done

	return 1
}


# Arguments:
	# $1 = Partition to scan
	# $2 = grep $2 from blkid

# $2 must be in the format 'TYPE=query', for example 'LABEL=kupfer_boot'
scan_partitions()
{
	local _partition="$1"
	local _query="$2"

	busybox echo "_partition is $_partition"
	busybox echo "_query is $_query"
	# Probe partition directly first
	! check_partition_type "$_partition" "$_query" || return 0

	# Then scan for subpartitions
	part_table_type=$(blkid -p -s PTTYPE -o value -n dos,gpt $_partition)
	if [ "$part_table_type" = "gpt" ] || [ "$part_table_type" = "dos" ]; then
		busybox echo "Found subpartitions at: $_partition"
		setup_loopdev "$_partition" || return 1
		! subpartition_probe "$_partition" "$_query" || return 0
	fi

	return 1
}
