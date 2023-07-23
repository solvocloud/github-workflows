#!/bin/bash -e

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ] ; then
  echo "Syntax: check-automated-tests.sh <s3 module name> <head ref> <artifacts bucket name> [<codebuild project name>]"
  exit 1
fi

MODULE_NAME=$1
HEAD_REF=$2
ARTIFACTS_BUCKET_NAME=$3
CODEBUILD_PROJECT_NAME=$4

echo "MODULE_NAME=${MODULE_NAME}, HEAD_REF=${HEAD_REF}, ARTIFACTS_BUCKET_NAME=${ARTIFACTS_BUCKET_NAME}, CODEBUILD_PROJECT_NAME=${CODEBUILD_PROJECT_NAME}"

REMOTE_BUILD_ID_FILE="s3://${ARTIFACTS_BUCKET_NAME}/${MODULE_NAME}/${HEAD_REF}/automated-tests-build-id.txt"

echo "Checking existence of remote automated tests build ID file: ${REMOTE_BUILD_ID_FILE}"

set +e
aws s3 ls ${REMOTE_BUILD_ID_FILE}
AWS_OUTPUT_RC=$?
set -e

if [ ${AWS_OUTPUT_RC} -ne 0 ] ; then
  if [ -n "${CODEBUILD_PROJECT_NAME}" ] ; then
    echo "Automated tests build ID file doesn't exist; looking for the build that builds ${HEAD_REF}"
    BUILD_IDS=$(aws codebuild list-builds-for-project --project-name ${CODEBUILD_PROJECT_NAME} --sort DESCENDING --no-paginate --output json | jq -r '.ids[]')
    RELEVANT_BUILD_ID=
    while IFS= read -r BUILD_ID ; do
      echo "Checking build ID: ${BUILD_ID}"
      RESOLVED_SOURCE_VERSION=$(aws codebuild batch-get-builds --ids ${BUILD_ID} --output text --query "builds[0].resolvedSourceVersion")
      echo "Resolved source version: ${RESOLVED_SOURCE_VERSION}"
      if [ "${RESOLVED_SOURCE_VERSION}" = "${HEAD_REF}" ] ; then
        RELEVANT_BUILD_ID=${BUILD_ID}
        break
      fi
    done <<< "${BUILD_IDS}"

    if [ -z "${RELEVANT_BUILD_ID}" ] ; then
      echo "Failed finding relevant build ID for ref ${HEAD_REF}"
      exit 1
    fi

    echo "Found relevant build ID: ${RELEVANT_BUILD_ID}, will wait for it to end"

    while true; do
      LAST_BUILD_STATUS=$(aws codebuild batch-get-builds --ids ${RELEVANT_BUILD_ID} --query "builds[0].buildStatus" --output text)
      echo "Last build status: ${LAST_BUILD_STATUS}"
      if [ "${LAST_BUILD_STATUS}" != "IN_PROGRESS" ] ; then
        break
      fi
      echo "Will retry in 10 seconds"
      sleep 10
    done

    echo "Build ${RELEVANT_BUILD_ID} ended"

    if [ "${LAST_BUILD_STATUS}" != "SUCCEEDED" ] ; then
      echo "Last build of ${CODEBUILD_PROJECT_NAME} did not succeed; exiting"
      exit 1
    fi
  fi
fi

BUILD_ID_TEXT_FILE=$(mktemp)
aws s3 cp ${REMOTE_BUILD_ID_FILE} ${BUILD_ID_TEXT_FILE}
BUILD_ID=$(cat ${BUILD_ID_TEXT_FILE})

echo "Automated tests build ID: ${BUILD_ID}"

BUILD_STATUS="IN_PROGRESS"
while [ "$BUILD_STATUS" == "IN_PROGRESS" ]; do
  echo "Checking build status"
  BUILD=$(aws codebuild batch-get-builds --ids ${BUILD_ID})
  BUILD_STATUS=$(echo ${BUILD} | jq '.builds[0].buildStatus' -r)
  if [ "${BUILD_STATUS}" == "IN_PROGRESS" ]; then
    echo "Build is still in progress, waiting..."
  fi
  sleep 10
done

if [ "${BUILD_STATUS}" != "SUCCEEDED" ]; then
  echo "Automated tests build did not succeed"
  exit 1
fi

echo "Automated tests build succeeded"
