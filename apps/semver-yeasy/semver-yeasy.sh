#!/usr/bin/env bash

set -x

echo 'Monotools: semver-yeasy'

mode=$1
repo_type="$(echo $2 | tr '[[:lower:]]' '[[:upper:]]')"

# TODO: To complete this, check if if conditions use these env vars in the workflow 
GITVERSION_TAG_PROPERTY_PULL_REQUESTS='.MajorMinorPatch'
GITVERSION_TAG_PROPERTY_DEFAULT='.MajorMinorPatch'
GITVERSION_TAG_PROPERTY_DEVELOP='.MajorMinorPatch'
GITVERSION_TAG_PROPERTY_RELEASE='.MajorMinorPatch'
GITVERSION_TAG_PROPERTY_HOTFIX='.MajorMinorPatch'
GITVERSION_TAG_PROPERTY_MAIN='.MajorMinorPatch'
GITVERSION_CONFIG_SINGLE_APP='.gitversion.yml'
GITVERSION_CONFIG_MONOREPO=${GITVERSION_CONFIG_MONOREPO:-\$svc/.gitversion.yml}
JQ_EXEC_PATH=${JQ_EXEC_PATH:-jq}

env

# Check if GITVERSION_EXEC_PATH is set
if [ -z "${GITVERSION_EXEC_PATH}" ]; then
    echo "Error: GITVERSION_EXEC_PATH is not set. Please set the path to the GitVersion executable."
    exit 1
fi

TAG_PREFIX="${TAG_PREFIX:-v}"

# Parse --tag-prefix argument if provided
for arg in "$@"; do
    case $arg in
        --tag-prefix=*)
            TAG_PREFIX="${arg#*=}"
            shift
            ;;
    esac
done

log () {
    if [ "${ENV}" == "DEBUG" ]; then
        echo "$@" >> $GITHUB_OUTPUT
    fi
}

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
        # DIFF_SOURCE=$(git rev-parse "${DIFF_DEST}"^1)
        DIFF_SOURCE="${DIFF_DEST}^"
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

    printf 'diff_source=%s\n' "$DIFF_SOURCE" >> $GITHUB_OUTPUT
    printf 'diff_dest=%s\n' "$DIFF_DEST" >> $GITHUB_OUTPUT

    echo "diff_source='$DIFF_SOURCE'"
    echo "diff_dest='$DIFF_DEST'"

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
        changed_services=(`ls -1 apps | xargs -n 1 printf 'apps/%s\n'`)
        else
        changed_services=(`git diff "${DIFF_SOURCE}" "${DIFF_DEST}" --name-only | grep -o '^apps/[a-zA-Z0-9-]*' | sort | uniq`)
        fi

        changed_services_value=$(${JQ_EXEC_PATH} -Mc --null-input '$ARGS.positional' --args -- "${changed_services[@]}")
        changed_services_output="{\"value\":${changed_services_value}}"

        printf 'changed_services=%s\n' "$changed_services_output" >> $GITHUB_OUTPUT
        printf 'changed_services=%s\n' "$changed_services_output" 
    fi
;;

calculate-version)
    CONFIG_FILE_VAR="GITVERSION_CONFIG_${repo_type}"
    GITVERSION_OPTIONS="/b ${DIFF_DEST}"

    if [ "${repo_type}" = 'SINGLE_APP' ]; then
        service_versions_txt='## version bump\n'
        if [ "${SEMVERYEASY_CHANGED}" = 'true' ]; then
        CONFIG_FILE="${!CONFIG_FILE_VAR}"
        # ${GITVERSION_EXEC_PATH} $(pwd) /nonormalize /config "${CONFIG_FILE}"
        gitversion_calc=$(${GITVERSION_EXEC_PATH} $(pwd) /nonormalize /config "${CONFIG_FILE} ${GITVERSION_OPTIONS}")

            GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_SOURCE}" | sed 's|/.*$||' | tr '[[:lower:]]' '[[:upper:]]')"
            GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
            if [ "${GITVERSION_TAG_PROPERTY}" == "" ]; then
                GITVERSION_TAG_PROPERTY=${GITVERSION_TAG_PROPERTY_DEFAULT}
            fi

            if [ -z "${gitversion_calc}" ]; then
                echo "Error: gitversion_calc turned out to be empty. Please check the configuration file and the command."
                exit 1
            fi

            service_version=$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
        service_versions_txt+="${service_version}\n"
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
                svc_without_apps_prefix=$(echo "${svc}/" | sed "s|^apps/||")
                gitversion_calc_cmd="${GITVERSION_EXEC_PATH} $(pwd) /nonormalize /config ${CONFIG_FILE} /overrideconfig tag-prefix=${svc_without_apps_prefix}"
                log "Running calculation - '${gitversion_calc_cmd}'"
                gitversion_calc=$($gitversion_calc_cmd)

                if [ -z "${gitversion_calc}" ]; then
                    echo "Error: gitversion_calc turned out to be empty. Please check the configuration file and the command."
                    exit 1
                fi
                
                # Used for debugging
                log "gitversion_calc=$($gitversion_calc_cmd 2>&1)"
                exit_status=$?
                log "Exit status: $exit_status" >> $GITHUB_OUTPUT

                if [ "${GITHUB_EVENT_NAME}" = "push" ]; then
                    GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_DEST}" | sed 's|(/|^).*$||' | tr '[[:lower:]]' '[[:upper:]]')"
                else 
                    GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_SOURCE}" | sed 's|(/|^).*$||' | tr '[[:lower:]]' '[[:upper:]]')"
                fi

                GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
                if [ "${GITVERSION_TAG_PROPERTY}" == "" ]; then
                    GITVERSION_TAG_PROPERTY=${GITVERSION_TAG_PROPERTY_DEFAULT}
                    log "GITVERSION_TAG_PROPERTY=${GITVERSION_TAG_PROPERTY}"
                fi

                echo "GITVERSION_TAG_PROPERTY_NAME=${GITVERSION_TAG_PROPERTY_NAME}"
                echo "GITVERSION_TAG_PROPERTY=${GITVERSION_TAG_PROPERTY}"
                service_version=$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
                service_versions_txt+="- ${svc} - ${service_version}\n"
            done
        fi
    fi
    # fix multiline variables
    # from: https://github.com/actions/create-release/issues/64#issuecomment-638695206
    PR_BODY="<!-- This is an autogenerated section - #region start PR Description by monotools -->\n${service_versions_txt}\n<!-- #region end PR Description by monotools -->"

    echo "${PR_BODY}"
    echo "PR_BODY=$PR_BODY" >> $GITHUB_OUTPUT
;;

update-pr)
    PR_NUMBER=$(echo $GITHUB_REF | awk 'BEGIN { FS = "/" } ; { print $3 }')

    # Get the existing PR Description - the if condition is used to help in unit testing
    if [[ -z "${RUN_ENV}" ]]; then
        PR_DESCRIPTION=$(curl -sL -H "Authorization: token ${GITHUB_TOKEN}" "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" | ${JQ_EXEC_PATH} -r '.body')
    fi

    # Define region markers (trimmed, case-insensitive)
    REGION_START='<!-- This is an autogenerated section - #region start PR Description by monotools -->'
    REGION_END='<!-- #region end PR Description by monotools -->'

    # Remove leading/trailing whitespace for comparison
    trim() { awk '{$1=$1;print}'; }
    PR_DESCRIPTION_TRIMMED=$(echo "$PR_DESCRIPTION" | trim)

    # Use awk to replace the region if it exists, else prepend
    if echo "$PR_DESCRIPTION_TRIMMED" | grep -i -q "$(echo "$REGION_START" | trim)"; then
        # Replace the region
        # echo "LOL='bruh in if'" >> $GITHUB_OUTPUT
        UPDATED_PR_BODY=$(awk -v new="$SEMVERYEASY_PR_BODY" -v start="$REGION_START" -v end="$REGION_END" '
            BEGIN {ins=1}
            {
                line=tolower($0); gsub(/^[ \t]+|[ \t]+$/, "", line)
                # print "something"
                if (ins == 1 && line == tolower(start)) {
                    print start
                    print new
                    print end
                    ins=0
                    next
                }
                if (line == tolower(end)) {
                    ins=1
                    next
                }
                # if (ins == 1) 
                print $0
            }
        ' <<< "$PR_DESCRIPTION")
    else
        # Prepend the generated section
        if [[ -z "${PR_DESCRIPTION}" ]]; then 
            UPDATED_PR_BODY="${SEMVERYEASY_PR_BODY}"
        else
            UPDATED_PR_BODY="${PR_DESCRIPTION}\n${SEMVERYEASY_PR_BODY}"
        fi
    fi

    {
        echo "UPDATED_PR_BODY<<EOF"
        echo "$UPDATED_PR_BODY"
        echo "EOF"
    } >> $GITHUB_OUTPUT

    # Only update the PR if PR_DESCRIPTION was not empty (i.e., not a unit test)
    if [[ -z "${RUN_ENV}" ]]; then
        # Update the PR with the updated description
        ${JQ_EXEC_PATH} -nc --arg body "$UPDATED_PR_BODY" '{"body": $body}' | \
            curl -sL -X PATCH -d @- \
            -H "Content-Type: application/json" \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER"
    fi
;;

tag)
    CONFIG_FILE_VAR="GITVERSION_CONFIG_${repo_type}"

    # https://github.com/orgs/community/discussions/26560
    git config --global user.email 'github-actions[bot]@users.noreply.github.com'
    git config --global user.name 'github-actions'
    if [ "${repo_type}" = 'SINGLE_APP' ]; then
        if [ "${SEMVERYEASY_CHANGED}" = 'true' ]; then
        # ${GITVERSION_EXEC_PATH} $(pwd) /nonormalize /config "${CONFIG_FILE}"
        gitversion_calc=$(${GITVERSION_EXEC_PATH} $(pwd) /nonormalize /config "${CONFIG_FILE}")

        GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_SOURCE}" | sed 's|/.*$||' | tr '[[:lower:]]' '[[:upper:]]')"
        GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
        if [ "${GITVERSION_TAG_PROPERTY}" == "" ]; then
            GITVERSION_TAG_PROPERTY=${GITVERSION_TAG_PROPERTY_DEFAULT}
        fi

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
        git tag -a "${full_service_version}" -m "${full_service_version}"
        git push origin "${full_service_version}"
        fi
    else
        changed_services=( $SEMVERYEASY_CHANGED_SERVICES )
        for svc in "${changed_services[@]}"; do
        echo "calculation for ${svc}"
        CONFIG_FILE=${!CONFIG_FILE_VAR//\$svc/$svc}
        # ${GITVERSION_EXEC_PATH} $(pwd) /nonormalize /config "${svc}/.gitversion.yml"
        gitversion_calc=$(${GITVERSION_EXEC_PATH} $(pwd) /nonormalize /config "${svc}/.gitversion.yml")

        GITVERSION_TAG_PROPERTY_NAME="GITVERSION_TAG_PROPERTY_$(echo "${DIFF_SOURCE}" | sed 's|/.*$||' | tr '[[:lower:]]' '[[:upper:]]')"
        GITVERSION_TAG_PROPERTY=${!GITVERSION_TAG_PROPERTY_NAME}
        if [ "${GITVERSION_TAG_PROPERTY}" == "" ]; then
            GITVERSION_TAG_PROPERTY=${GITVERSION_TAG_PROPERTY_DEFAULT}
        fi

        service_version=$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r "[${GITVERSION_TAG_PROPERTY}] | join(\"\")")
        svc_without_prefix="$(echo "${svc}" | sed "s|^apps/||")"
        if [ "${GITVERSION_TAG_PROPERTY}" != ".MajorMinorPatch" ]; then
            previous_commit_count=$(git tag -l | grep "^${svc_without_prefix}/$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r ".MajorMinorPatch")-$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r ".PreReleaseLabel")" | grep -o -E '\.[0-9]+$' | grep -o -E '[0-9]+$' | sort -nr | head -1)
            next_commit_count=$((previous_commit_count+1))
            version_without_count=$(echo "${gitversion_calc}" | ${JQ_EXEC_PATH} -r "[.MajorMinorPatch,.PreReleaseLabelWithDash] | join(\"\")")
            full_service_version="${version_without_count}.${next_commit_count}"
        else
            full_service_version="${service_version}"
        fi
        git tag -a "${svc_without_prefix}/${full_service_version}" -m "${svc_without_prefix}/${full_service_version}"
        git push origin "${svc_without_prefix}/${full_service_version}"
        done
    fi
;;

*)
    echo 'Not a valid mode. Exiting...'
    exit 0
;;

esac

set +x
