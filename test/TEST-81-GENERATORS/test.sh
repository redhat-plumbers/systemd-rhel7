#!/usr/bin/bash
TEST_DESCRIPTION="Test systemd generators"

# shellcheck source=test/test-functions
. "$TEST_BASE_DIR/test-functions"

check_result_qemu() {
    ret=1
    mkdir -p $TESTDIR/root
    mount ${LOOPDEV}p1 $TESTDIR/root
    [[ -e $TESTDIR/root/testok ]] && ret=0
    [[ -f $TESTDIR/root/failed ]] && cp -a $TESTDIR/root/failed $TESTDIR
    [[ -f $TESTDIR/root/var/log/journal ]] && cp -a $TESTDIR/root/var/log/journal $TESTDIR
    umount $TESTDIR/root
    [[ -f $TESTDIR/failed ]] && cat $TESTDIR/failed
    ls -l $TESTDIR/journal/*/*.journal
    test -s $TESTDIR/failed && ret=$(($ret+1))
    return $ret
}

test_run() {
    if run_qemu; then
        check_result_qemu || return 1
    else
        dwarn "can't run QEMU, skipping"
    fi
    if check_nspawn; then
        run_nspawn
        check_result_nspawn || return 1
    else
        dwarn "can't run systemd-nspawn, skipping"
    fi
    return 0
}

test_setup() {
    create_empty_image
    mkdir -p "${TESTDIR:?}/root"
    mount "${LOOPDEV:?}p1" "$TESTDIR/root"

    (
        LOG_LEVEL=5
        # shellcheck disable=SC2046
        eval $(udevadm info --export --query=env --name="${LOOPDEV}p2")

        setup_basic_environment

        # mask some services that we do not want to run in these tests
        ln -fs /dev/null "$initdir/etc/systemd/system/systemd-hwdb-update.service"
        ln -fs /dev/null "$initdir/etc/systemd/system/systemd-journal-catalog-update.service"
        ln -fs /dev/null "$initdir/etc/systemd/system/systemd-networkd.service"
        ln -fs /dev/null "$initdir/etc/systemd/system/systemd-networkd.socket"
        ln -fs /dev/null "$initdir/etc/systemd/system/systemd-resolved.service"
        ln -fs /dev/null "$initdir/etc/systemd/system/systemd-machined.service"

        # setup the testsuite service
        cat >"$initdir/etc/systemd/system/testsuite.service" <<EOF
[Unit]
Description=Testsuite service

[Service]
ExecStart=/bin/bash -x /testsuite.sh
Type=oneshot
StandardOutput=tty
StandardError=tty
NotifyAccess=all
EOF
        cp generator-utils.sh testsuite*.sh "$initdir/"

        setup_testsuite
    ) || return 1
    setup_nspawn_root

    ddebug "umount $TESTDIR/root"
    umount "$TESTDIR/root"
}

test_cleanup() {
    umount $TESTDIR/root 2>/dev/null
    [[ $LOOPDEV ]] && losetup -d $LOOPDEV
    return 0
}

do_test "$@"
