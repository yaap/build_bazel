#!/usr/bin/env bash

# Copyright (C) 2023 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# A script to test the end-to-end flow of atest --roboleaf-mode on the Android
# CI.

set -euo pipefail
set -x

function get_build_var()
{
  (${PWD}/build/soong/soong_ui.bash --dumpvar-mode --abs $1)
}

if [ ! -n "${ANDROID_BUILD_TOP}" ] ; then
  export ANDROID_BUILD_TOP=${PWD}
fi

if [ ! -n "${TARGET_PRODUCT}" ] || [ ! -n "${TARGET_BUILD_VARIANT}" ] ; then
  export \
    TARGET_PRODUCT=aosp_x86_64 \
    TARGET_BUILD_VARIANT=userdebug
fi

remote_cache="grpcs://${FLAG_service%:*}"

out=$(get_build_var PRODUCT_OUT)

# ANDROID_BUILD_TOP is deprecated, so don't use it throughout the script.
# But if someone sets it, we'll respect it.
cd ${ANDROID_BUILD_TOP:-.}

# Use the versioned Python binaries in prebuilts/ for a reproducible
# build with minimal reliance on host tools. Add build/bazel/bin to PATH since
# atest needs 'b'
export PATH=${PWD}/prebuilts/build-tools/path/linux-x86:${PWD}/build/bazel/bin:${PATH}

export \
  ANDROID_PRODUCT_OUT=${out} \
  OUT=${out} \
  ANDROID_HOST_OUT=$(get_build_var HOST_OUT) \
  ANDROID_TARGET_OUT_TESTCASES=$(get_build_var TARGET_OUT_TESTCASES) \

build/soong/soong_ui.bash --make-mode bp2build --skip-soong-tests

build/soong/soong_ui.bash --make-mode atest --skip-soong-tests

${OUT_DIR}/host/linux-x86/bin/atest-dev \
  --roboleaf-mode=dev \
  --bazel-arg=--config=remote_avd \
  --bazel-arg=--config=ci \
  --bazel-arg=--bes_keywords="${ROBOLEAF_BES_KEYWORDS}" \
  --bazel-arg=--bes_results_url="${ROBOLEAF_BES_RESULTS_URL}" \
  --bazel-arg=--remote_cache="${remote_cache}" \
  --bazel-arg=--project_id="${BES_PROJECT_ID}" \
  --bazel-arg=--build_metadata=ab_branch="${BRANCH_NAME}" \
  --bazel-arg=--build_metadata=ab_target="${BUILD_TARGET_NAME}" \
  --bazel-arg=--build_metadata=ab_build_id="${BUILD_NUMBER}" \
  "$@" \
  HelloWorldHostTest \
  sysprop_test \
  merge_annotation_zips_test \
  adbd_test \
  HelloWorldTests \
  CtsGestureTestCases
