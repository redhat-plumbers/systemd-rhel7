#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later

link_endswith() {
    [[ -h "${1:?}" && "$(readlink "${1:?}")" =~ ${2:?}$ ]]
}

link_eq() {
    [[ -h "${1:?}" && "$(readlink "${1:?}")" == "${2:?}" ]]
}

# Get the value from a 'key=value' assignment
opt_get_arg() {
    local arg

    IFS="=" read -r _ arg <<< "${1:?}"
    test -n "$arg"
    echo "$arg"
}

in_initrd() {
    [[ "${SYSTEMD_IN_INITRD:-0}" -ne 0 ]]
}

# Check if we're parsing host's fstab in initrd
in_initrd_host() {
    in_initrd && [[ "${SYSTEMD_SYSROOT_FSTAB:-/dev/null}" != /dev/null ]]
}

in_container() {
    systemd-detect-virt -qc
}

opt_filter() (
    set +x
    local opt split_options filtered_options

    IFS="," read -ra split_options <<< "${1:?}"
    for opt in "${split_options[@]}"; do
        if [[ "$opt" =~ ${2:?} ]]; then
            continue
        fi

        filtered_options+=("$opt")
    done

    IFS=","; printf "%s" "${filtered_options[*]}"
)

# Run the given generator $1 with target directory $2 - clean the target
# directory beforehand
run_and_list() {
    local generator="${1:?}"
    local out_dir="${2:?}"
    local environ
    local cmdline

    # If $PID1_ENVIRON is set temporarily overmount /proc/1/environ with
    # a temporary file that contains contents of $PID1_ENVIRON. This is
    # necessary in cases where the generator reads the environment through
    # getenv_for_pid(1, ...) or similar like getty-generator does.
    #
    # Note: $PID1_ENVIRON should be a NUL separated list of env assignments
    if [[ -n "${PID1_ENVIRON:-}" ]]; then
        environ="$(mktemp)"
        echo -ne "${PID1_ENVIRON}\0" >"${environ:?}"
        mount -v --bind "$environ" /proc/1/environ
    fi

    if [[ -n "${SYSTEMD_PROC_CMDLINE:-}" ]]; then
        cmdline="$(mktemp)"
        echo "$SYSTEMD_PROC_CMDLINE" >"$cmdline"
        mount --bind "$cmdline" /proc/cmdline
    fi

    if [[ -n "${SYSTEMD_FSTAB:-}" ]]; then
        touch /etc/fstab
        mount --bind "$SYSTEMD_FSTAB" /etc/fstab
    fi

    if [[ -n "${SYSTEMD_SYSROOT_FSTAB:-}" ]]; then
        mkdir -p /sysroot/etc
        touch /sysroot/etc/fstab
        mount --bind "$SYSTEMD_SYSROOT_FSTAB" /sysroot/etc/fstab
    fi

    rm -fr "${out_dir:?}"/*
    mkdir -p "$out_dir"/{normal,early,late}
    SYSTEMD_LOG_LEVEL="${SYSTEMD_LOG_LEVEL:-debug}" "$generator" "$out_dir/normal" "$out_dir/early" "$out_dir/late"
    ls -lR "$out_dir"

    if [[ -n "${SYSTEMD_SYSROOT_FSTAB:-}" ]]; then
        umount /sysroot/etc/fstab
        rm -rf /sysroot
    fi

    if [[ -n "${SYSTEMD_FSTAB:-}" ]]; then
        umount /etc/fstab
    fi

    if [[ -n "${SYSTEMD_PROC_CMDLINE:-}" ]]; then
        umount /proc/cmdline
        rm -f "$cmdline"
    fi

    if [[ -n "${environ:-}" ]]; then
        umount /proc/1/environ
        rm -f "$environ"
    fi
}
