#!/usr/bin/env bash

ROOT=`pwd`
REPO_ROOT=`dirname $0`
cd ${REPO_ROOT}
REPO_ROOT=`pwd`
REPO_ROOT=$(dirname $(dirname ${REPO_ROOT}))
SEMVERYEASY_ROOT="${REPO_ROOT}/apps/semver-yeasy"
TESTS_TMP="${SEMVERYEASY_ROOT}/__tests_tmp__"

mkdir "${TESTS_TMP}"
TEST_REPO="${TESTS_TMP}/repo"

echo '
mode: MainLine
tag-prefix: v
branches:
  main:
    increment: Minor
  release:
    increment: None
  feature:
    regex: ^(feat|fix|improv|chore)[/-]
    commit-message-incrementing: Enabled
    tag: alpha
    increment: Minor
  hotfix:
    tag: hotfix
    increment: Patch
' > "${TESTS_TMP}/gitversion.yml"

echo "
# set -x

# apk add bash jq

git config --global user.email 'example@example.com'
git config --global user.name 'Example'



mkdir ${TEST_REPO}
cd ${TEST_REPO}
git init .
mkdir -p \"${TEST_REPO}/.cicd/common\"
cp \"${TESTS_TMP}/gitversion.yml\" \"${TEST_REPO}/.cicd/common\"
git commit -am 'initial commit' --allow-empty
git tag -a 'v0.1.0' -m 'v0.1.0'
git checkout -b develop
git commit -m 'one commit' --allow-empty

bash ${REPO_ROOT}/apps/semver-yeasy/semver-yeasy.sh calculate-version

" > "${TESTS_TMP}/entrypoint.sh"

GITVERSION_REPO_TYPE='SINGLE_APP' SEMVERYEASY_CHANGED='true' GITVERSION='gittools/gitversion:5.10.0-alpine.3.14-6.0' . "${TESTS_TMP}/entrypoint.sh"

rm -rf "${TESTS_TMP}"
