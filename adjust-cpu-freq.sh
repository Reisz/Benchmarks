#!/bin/sh

khz_to_mhz() {
    _decimals="$1"

    # Last three digits
    while [ "${#_decimals}" != 3 ]; do
    _decimals="${_decimals#?}"
    done

    # Remove trailing zeroes
    while [ "${_decimals%0}" != "$_decimals" ]; do
        _decimals="${_decimals%?}"
    done

    # Add decimal point if applicable
    if [ "$_decimals" ]; then
    _decimals=".$_decimals"
    fi

    printf '%s%s' "${1%???}" "$_decimals"
}

to_nearest_1k() {
    _left="${1%.*}"
    _right="${1#*.}"

    # Right will be the same as left if there was no dot
    # Setting it to the empty string to represent no digits after dot
    if [ "$_left.$_right" != "$1" ]; then
    _right=""
    fi

    # Adjust decimals to multiple of 1000
    while [ $((${#_right} % 3)) != 0 ]; do
    _right="${_right}0"
    done

    printf '%s%s' "$_left" "$_right"
}

# Need to be root
if [ "$(whoami)" != 'root' ]; then
    echo 'Error: Need root privileges to change cpu scaling.'
    exit 1
fi

if [ "$1" ]; then
    # Normalize decimal input
    _freq="$(to_nearest_1k "$1")"

    # Try to recoginze requested unit
    if [ "$_freq" -lt 10 ]; then
        # Requested unit is GHz
        _freq=$((_freq * 1000000))
    elif [ "$_freq" -lt 10000 ]; then
        # Requested unit is MHz
        _freq=$((_freq * 1000))
    else
        # Requested unit is kHz
        _freq="$_freq"
    fi

    printf 'Requesting %sMHz\n\n' "$(khz_to_mhz "$_freq")"
fi

for _cpu in /sys/devices/system/cpu/cpu*[0-9]; do
    # Governor should be `userspace` if available. Use `performance` as fallback (for intel_psave).
    if [ "$(cat "$_cpu/cpufreq/scaling_governor")" != "userspace" ]; then
        # Check for userspace and performance in available governors and set userspace if applicable
        # We want to loop over each word:
        # shellcheck disable=SC2013
        for _gov in $(cat "$_cpu/cpufreq/scaling_available_governors"); do
            if [ "$_gov" = "userspace" ]; then
                _has_userspace=1
                echo "Setting $(basename "$_cpu") governor to 'userspace'."
                echo 'userspace' > "$_cpu/cpufreq/scaling_governor"
                break
            elif [ "$_gov" = "performance" ]; then
                _has_performance=1
            fi
        done

        # No userspace governor available
        if [ -z "$_has_userspace" ]; then
            # Warn if desired frequency was provided
            if [ "$1" ]; then
                echo "Warning: Could not set desired frequency for $(basename "$_cpu")"
            fi

            # Abort if no applicable governor
            if [ -z "$_has_performance" ]; then
                echo "Error: No applicable governor found for $(basename "$_cpu")"
                exit 1
            fi

            # Set to performance as a fallback
            echo "Setting $(basename "$_cpu") governor to 'performance'."
            echo 'performance' > "$_cpu/cpufreq/scaling_governor"
        fi
    else
        _has_userspace=1
    fi

    # Set desired frequency
    if [ "$_freq" ] && [ "$_has_userspace" ]; then
        # Find appropriate frequency in available frequencies
        # We want to loop over each word:
        # shellcheck disable=SC2013
        for _avail in $(cat "$_cpu/cpufreq/scaling_available_frequencies"); do
            if [ "$_avail" = "$_freq" ]; then
                _nearest="$_freq"
                break
            else
                # Get absolute distance
                if [ "$_freq" -lt "$_avail" ]; then
                    _dist=$((_avail - _freq))
                else
                    _dist=$((_freq - _avail))
                fi

                # Update nearest
                if [ -z "$_min_dist" ] || [ "$_min_dist" -gt "$_dist" ]; then
                    _nearest="$_avail"
                    _min_dist="$_dist"
                fi
            fi
        done

        # Exact frequency not found
        if [ "$_nearest" != "$_freq" ]; then
            echo "Warning: Excact requested frequency not found, using nearest alternative."
        fi

        printf 'Setting %s frequency to %sMHz\n' "$(basename "$_cpu")" "$(khz_to_mhz "$_nearest")"
        echo "$_nearest" > "$_cpu/cpufreq/scaling_setspeed"
    elif [ $_has_userspace ]; then
        printf 'Keeping %s frequency at %sMHz\n' "$(basename "$_cpu")" "$(khz_to_mhz "$(cat "$_cpu/cpufreq/scaling_cur_freq")")"
    fi
done
