#!/bin/sh
DISK="/dev/nvme0n1p3"

fido2_device() {
    device=$(fido2-token -L | sed 's/:.*//')
    if [ -z "$device" ] ; then
        return 1
    else
        echo "$device"
    fi
}

fido2_get_token() {
    token_id=$(cryptsetup luksDump "$DISK" | grep -E '^\s+[0-9]+: systemd-fido2$' | head -1 | sed -e 's/\s\+\([0-9]\+\):.*/\1/')
    cryptsetup token export "$DISK" --token-id=$token_id
}

fido2_authenticate() {
    token_json=$(fido2_get_token)
    param_file=$(mktemp)
    dd if=/dev/urandom bs=1 count=32 2> /dev/null | base64 > $param_file
    echo $token_json | jq -r '."fido2-rp"' >> $param_file
    echo $token_json | jq -r '."fido2-credential"' >> $param_file
    echo $token_json | jq -r '."fido2-salt"' >> $param_file

    assert_flags="-G -h"
    assert_flags="$assert_flags -t pin=$(echo $token_json | jq -r '."fido2-clientPin-required"')"
    assert_flags="$assert_flags -t up=$(echo $token_json | jq -r '."fido2-up-required"')"
    assert_flags="$assert_flags -t uv=$(echo $token_json | jq -r '."fido2-uv-required"')"

    assertion=$(echo "$1" | setsid fido2-assert $assert_flags -i "$param_file" $(fido2_device) 2> /dev/null || (rm -f $param_file ; echo "Wrong PIN." 1>&2 ; exit 1))
    rm -f $param_file
    printf '%s' "$assertion" | tail -1
}