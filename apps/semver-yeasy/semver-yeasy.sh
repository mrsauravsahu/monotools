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

changed)
    if [ "${GITHUB_EVENT_NAME}" = 'push' ]; then
        DIFF_DEST="${GITHUB_REF_NAME}"
        DIFF_SOURCE=$(git rev-parse "${DIFF_DEST}"^1)
    else
        DIFF_DEST="${GITHUB_HEAD_REF}"
        DIFF_SOURCE="${GITHUB_BASE_REF}"
    fi
    # use main as source if current branch is a release branch
    if [ "$(echo "${DIFF_DEST}" | grep -o '^release/')" = "release/" ]; then
        DIFF_SOURCE="main"
    fi
    # use main as source if current branch is a hotfix branch
    if [ "$(echo "${DIFF_DEST}" | grep -o '^hotfix/')" = "hotfix/" ]; then
        DIFF_SOURCE="main"
    fi
    echo "::set-output name=diff_source::$DIFF_SOURCE"
    echo "::set-output name=diff_dest::$DIFF_DEST"
    echo "DIFF_SOURCE='$DIFF_SOURCE'"
    echo "DIFF_DEST='$DIFF_DEST'"

    # setting empty outputs otherwise next steps fail during preprocessing stage
    echo "::set-output name=changed::''"
    echo "::set-output name=changed_services::''"

    # service change calculation with diff - ideally use something like 'plz' or 'bazel'
    if [ "${GITVERSION_REPO_TYPE}" = 'SINGLE_APP' ]; then
        if [ `git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -o '^src/' | sort | uniq` = 'src/' ]; then
        changed=true
        else
        changed=false
        fi
        echo "changed='${changed}'"
        echo "::set-output name=changed::$changed"
    else
        if [ "$(git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -o '^common/' > /dev/null && echo 'common changed')" = 'common changed' ]; then
        changed_services=`ls -1 apps | xargs -n 1 printf 'apps/%s\n'`
        else
        changed_services=`git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -o '^apps/[a-zA-Z-]*' | sort | uniq`
        fi
        changed_services=$(printf '%s' "$changed_services" | jq --raw-input --slurp '.')
        echo "::set-output name=changed_services::$changed_services"
        echo "changed_services='$(echo "$changed_services" | sed 'N;s/\n/, /g')'"
    fi
;;

*)
    echo 'Not a valid mode. Exiting...'
    exit 0
;;

esac