#!/bin/bash -e

MODULE_NAME=$1
HEAD_REF=$2
ARTIFACTS_BUCKET_NAME=$3

echo "HEAD_REF=${HEAD_REF}, ARTIFACTS_BUCKET_NAME=${ARTIFACTS_BUCKET_NAME}"

BUILD_ID_TEXT_FILE=$(mktemp)
aws s3 cp s3://${ARTIFACTS_BUCKET_NAME}/${MODULE_NAME}/${HEAD_REF}/automated-tests-build-id.txt ${BUILD_ID_TEXT_FILE}
BUILD_ID=$(cat ${BUILD_ID_TEXT_FILE})

echo "Automated tests build ID: ${BUILD_ID}"

BUILD_STATUS="IN_PROGRESS"
while [ "$BUILD_STATUS" == "IN_PROGRESS" ]; do
  echo "Checking build status."
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
