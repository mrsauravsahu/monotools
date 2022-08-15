#!/usr/bin/env bash

echo 'Monotools: semver-yeasy'

mode=$1

case "${mode}" in

checkout)
    if [ "${GITHUB_EVENT_NAME}" = 'push' ]; then
        DIFF_DEST="${GITHUB_REF_NAME}"
    else
        DIFF_DEST="${GITHUB_HEAD_REF}"
    fi
    git checkout ${DIFF_DEST}
;;

*)
    echo 'Not a valid mode. Exiting...'
    exit 0
;;

esac