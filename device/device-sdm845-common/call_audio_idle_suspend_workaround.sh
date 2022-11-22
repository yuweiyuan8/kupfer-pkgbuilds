#!/bin/bash

NOTFOUND="NOT_FOUND"


interface=org.freedesktop.ModemManager1.Call
member=StateChanged


find_proc_uid() {
	local uid="$NOTFOUND"
	local pid="$1"
	local procdir="/proc/$pid"
	if [ -n "$pid" ] && [ -e "$procdir" ]
	then
		if _uid="$(stat -c '%u' "$procdir")" && [ -n "$_uid" ]; then
			uid="$_uid"
		fi
	fi
	echo "$uid"
}

find_pulse_pid() {
	pgrep -n '^(.*/)?pulseaudio$' || echo "$NOTFOUND"
}


pulsepid="$(find_pulse_pid)"
userid="$(find_proc_uid "$pulsepid")"
user="$(getent passwd "$userid" | cut -d: -f1)"

dbus-monitor --system "type='signal',interface='$interface',member='$member'" |
while read -r line ; do
	state=$(echo $line | grep -w "int32" | awk '{print $2}')
	if [ -z $state ]
	then
		: # Ignore if empty
	else
		if ! ([ -n "$pulsepid" ] && [ -e "/proc/$pulsepid" ])
		then
			pulsepid="$(find_pulse_pid)"
			userid="$(find_proc_uid "$pulsepid")"
			user="$(getent passwd "$userid" | cut -d: -f1)"
		fi
		if ! ([ -n "$pulsepid" ] && [ -e "/proc/$pulsepid" ])
		then
			echo "FAILED TO FIND PULSE! COULDN'T HANDLE STATE CHANGE $state"
			continue
		fi
		# Call State is based on https://www.freedesktop.org/software/ModemManager/doc/latest/ModemManager/ModemManager-Flags-and-Enumerations.html#MMCallState
		if [ $state -eq '0' ]
		then
			echo "Call Started"

			# Unload module-suspend-on-idle when call begins
			su "$user" -s /bin/sh -c "env 'XDG_RUNTIME_DIR=/run/user/$userid' pactl unload-module module-suspend-on-idle"
		fi

		if [ $state -eq '7' ]
		then
			echo "Call Ended"

			# Reload module-suspend-on-idle after call ends
			su "$user" -s /bin/sh -c "env 'XDG_RUNTIME_DIR=/run/user/$userid' pactl load-module module-suspend-on-idle"
		fi
	fi
done
