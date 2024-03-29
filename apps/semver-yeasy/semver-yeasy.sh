#!/usr/bin/env bash

echo 'Monotools: semver-yeasy'

mode=$1
repo_type="$(echo $2 | tr '[[:lower:]]' '[[:upper:]]')"

# TODO: To complete this, check if if conditions use these env vars in the workflow 
GITVERSION_TAG_PROPERTY_PULL_REQUESTS='.SemVer'
GITVERSION_TAG_PROPERTY_DEFAULT='.SemVer'
GITVERSION_TAG_PROPERTY_DEVELOP='.SemVer'
GITVERSION_TAG_PROPERTY_RELEASE='.SemVer'
GITVERSION_TAG_PROPERTY_HOTFIX='.SemVer'
GITVERSION_TAG_PROPERTY_MAIN='.MajorMinorPatch'
GITVERSION_CONFIG_SINGLE_APP='.gitversion.yml'
GITVERSION_CONFIG_MONOREPO='$svc/.gitversion.yml'
JQ_EXEC_PATH="${JQ_EXEC_PATH:-jq}"

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
    echo "diff_source=$DIFF_SOURCE" >> $GITHUB_OUTPUT
    echo "diff_dest=$DIFF_DEST" >> $GITHUB_OUTPUT
    echo "DIFF_SOURCE='$DIFF_SOURCE'"
    echo "DIFF_DEST='$DIFF_DEST'"

    # setting empty outputs otherwise next steps fail during preprocessing stage
    echo "changed=''" >> $GITHUB_OUTPUT
    echo "changed_services=''" >> $GITHUB_OUTPUT

    # service change calculation with diff - ideally use something like 'plz' or 'bazel'
    if [ "${repo_type}" = 'SINGLE_APP' ]; then
        if [ `git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -o '^src/' | sort | uniq` = 'src/' ]; then
        changed=true
        else
        changed=false
        fi
        echo "changed='${changed}'"
        echo "changed=$changed" >> $GITHUB_OUTPUT
    else
        if [ "$(git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -o '^common/' > /dev/null && echo 'common changed')" = 'common changed' ]; then
        changed_services=`ls -1 apps | xargs -n 1 printf 'apps/%s\n'`
        else
        changed_services=`git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -o '^apps/[a-zA-Z0-9-]*' | sort | uniq`
        fi

        if [ "${ENV}" != "LOCAL" ]; then
            changed_services=$(printf '%s' "$changed_services" | ${JQ_EXEC_PATH} --raw-input --slurp '.')
        fi
        echo "changed_services=\"$changed_services\"" >> $GITHUB_OUTPUT
        echo "changed_services='$(echo "$changed_services" | sed 'N;s/\n/, /g')'"
    fi


;;

calculate-version)
    CONFIG_FILE_VAR="GITVERSION_CONFIG_${repo_type}"
    if [ "${repo_type}" = 'SINGLE_APP' ]; then
        service_versions_txt='## version bump\n'
        if [ "${SEMVERYEASY_CHANGED}" = 'true' ]; then
        ${GITVERSION_EXEC_PATH} $(pwd) /config "${CONFIG_FILE}"
        gitversion_calc=$(${GITVERSION_EXEC_PATH} $(pwd) /config "${CONFIG_FILE}")
            GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_DEST}" | sed 's|/.*$||' | tr '[[:lower:]]' '[[:upper:]]')"
            GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
            service_version=$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
        service_versions_txt+="v${service_version}\n"
        else
        service_versions_txt+='\nNo version bump required\n'
        fi
    else
        service_versions_txt='## impact surface\n'
        changed_services=( $SEMVERYEASY_CHANGED_SERVICES )
        if [ "${#changed_services[@]}" = "0" ]; then
        service_versions_txt+='No services changed\n'
        else
        service_versions_txt="## impact surface\n"
        for svc in "${changed_services[@]}"; do
            CONFIG_FILE="${!CONFIG_FILE_VAR}"
            CONFIG_FILE=$(echo "${CONFIG_FILE}" | sed "s|\$svc|$svc|")
            gitversion_calc_cmd="${GITVERSION_EXEC_PATH} $(pwd) /config ${CONFIG_FILE}"
            gitversion_calc=$($gitversion_calc_cmd)
            
            # Used for debugging
            # gitversion_calc=$($gitversion_calc_cmd 2>&1) >> $GITHUB_OUTPUT
            # exit_status=$?
            # echo "Exit status: $exit_status" >> $GITHUB_OUTPUT
            
            GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_PULL_REQUESTS"
            GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
            GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_DEST}" | sed 's|/.*$||' | tr '[[:lower:]]' '[[:upper:]]')"
            GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
            service_version=$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
            service_versions_txt+="- ${svc} - v${service_version}\n"
        done
        fi
    fi
    # fix multiline variables
    # from: https://github.com/actions/create-release/issues/64#issuecomment-638695206
    PR_BODY="${service_versions_txt}"

    if [ "${ENV}" != "LOCAL" ]; then
        PR_BODY=$(printf '%s' "$PR_BODY" | ${JQ_EXEC_PATH} --raw-input --slurp '.')
    fi
    echo "${PR_BODY}"
    echo "PR_BODY=$PR_BODY" >> $GITHUB_OUTPUT
;;

update-pr)
    PR_NUMBER=$(echo $GITHUB_REF | awk 'BEGIN { FS = "/" } ; { print $3 }')

    # Get the existing PR description
    PR_DESCRIPTION=$(curl -sL -H "Authorization: token ${GITHUB_TOKEN}" "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" | ${JQ_EXEC_PATH} -r '.body')

    # Update the PR description
    UPDATED_DESCRIPTION=$(echo "$PR_DESCRIPTION" | sed -e '/\[comment\]: # \(START semver-yeasy\)/ {i\ $SEMVERY_YEASY_PR_BODY}' -e '/\[comment\]: # \(END semver-yeasy\)/ {a\ $SEMVERY_YEASY_PR_BODY}')

    if [[ -z "$UPDATED_DESCRIPTION" ]]; then
        UPDATED_DESCRIPTION="$SEMVERY_YEASY_PR_BODY"
    fi

    # Update the PR with the updated description
    curl -sL -X PATCH -d "{\"body\": \"$UPDATED_DESCRIPTION\" }" \
        -H "Content-Type: application/json" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER"
;;

tag)
    CONFIG_FILE_VAR="GITVERSION_CONFIG_${repo_type}"

    # https://github.com/orgs/community/discussions/26560
    git config --global user.email 'github-actions[bot]@users.noreply.github.com'
    git config --global user.name 'github-actions'
    if [ "${repo_type}" = 'SINGLE_APP' ]; then
        if [ "${SEMVERYEASY_CHANGED}" = 'true' ]; then
        ${GITVERSION_EXEC_PATH} $(pwd) /config "${CONFIG_FILE}"
        gitversion_calc=$(${GITVERSION_EXEC_PATH} $(pwd) /config "${CONFIG_FILE}")
        GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_DEST}" | sed 's|/.*$||' | tr '[[:lower:]]' '[[:upper:]]')"
        GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
        service_version=$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
        if [ "${GITVERSION_TAG_PROPERTY}" != ".MajorMinorPatch" ]; then
            svc_without_prefix='v'
            previous_commit_count=$(git tag -l | grep "^${svc_without_prefix}$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r ".MajorMinorPatch")-$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r ".PreReleaseLabel")" | grep -o -E '\.[0-9]+$' | grep -o -E '[0-9]+$' | sort -nr | head -1)
            next_commit_count=$((previous_commit_count+1))
            version_without_count=$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r "[.MajorMinorPatch,.PreReleaseLabelWithDash] | join(\"\")")
            full_service_version="${version_without_count}.${next_commit_count}"
        else
            full_service_version="${service_version}"
        fi
        git tag -a "v${full_service_version}" -m "v${full_service_version}"
        git push origin "v${full_service_version}"
        fi
    else
        changed_services=( $SEMVERYEASY_CHANGED_SERVICES )
        for svc in "${changed_services[@]}"; do
        echo "calculation for ${svc}"
        CONFIG_FILE=${!CONFIG_FILE_VAR//\$svc/$svc}
        ${GITVERSION_EXEC_PATH} $(pwd) /config "${svc}/.gitversion.yml"
        gitversion_calc=$(${GITVERSION_EXEC_PATH} $(pwd) /config "${svc}/.gitversion.yml")
        GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_DEST}" | sed 's|/.*$||' | tr '[[:lower:]]' '[[:upper:]]')"
        GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
        service_version=$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
        svc_without_prefix="$(echo "${svc}" | sed "s|^apps/||")"
        if [ "${GITVERSION_TAG_PROPERTY}" != ".MajorMinorPatch" ]; then
            previous_commit_count=$(git tag -l | grep "^${svc_without_prefix}/v$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r ".MajorMinorPatch")-$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r ".PreReleaseLabel")" | grep -o -E '\.[0-9]+$' | grep -o -E '[0-9]+$' | sort -nr | head -1)
            next_commit_count=$((previous_commit_count+1))
            version_without_count=$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r "[.MajorMinorPatch,.PreReleaseLabelWithDash] | join(\"\")")
            full_service_version="${version_without_count}.${next_commit_count}"
        else
            full_service_version="${service_version}"
        fi
        git tag -a "${svc_without_prefix}/v${full_service_version}" -m "${svc_without_prefix}/v${full_service_version}"
        git push origin "${svc_without_prefix}/v${full_service_version}"
        done
    fi
;;

*)
    echo 'Not a valid mode. Exiting...'
    exit 0
;;

esac
