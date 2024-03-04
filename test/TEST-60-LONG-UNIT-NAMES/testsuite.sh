#!/bin/bash

set -eux
set -o pipefail

systemd-analyze set-log-level debug

# make sure we can handle mounts at very long paths such that mount unit name must be hashed to fall within our unit name limit
LONGPATH="$(printf "/$(printf "x%0.s" {1..255})%0.s" {1..7})"
LONGMNT="$(systemd-escape --suffix=mount --path "$LONGPATH")"
TS="$(date '+%H:%M:%S')"

mkdir -p "$LONGPATH"
mount -t tmpfs tmpfs "$LONGPATH"
systemctl daemon-reload

# check that unit is active(mounted)
systemctl --no-pager show -p SubState "$LONGPATH" | grep -q mounted

# check that relevant part of journal doesn't contain any errors related to unit
[ "$(journalctl -b --since="$TS" --priority=err | grep -c "$LONGMNT")" = "0" ]

# check that we can successfully stop the mount unit
systemctl stop "$LONGPATH"
rm -rf "$LONGPATH"

systemd-analyze set-log-level info

echo OK > /testok
exit 0
