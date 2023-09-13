#!/bin/bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
MODULE_NAME="{module_name}"
ATEST_TF_LAUNCHER="{atest_tradefed_launcher}"
ATEST_HELPER="{atest_helper}"
TRADEFED_CLASSPATH="{tradefed_classpath}"
PATH_ADDITIONS="{path_additions}"
TEST_FILTER_OUTPUT="{test_filter_output}"
read -a ADDITIONAL_TRADEFED_OPTIONS <<< "{additional_tradefed_options}"

export PATH="${PATH_ADDITIONS}:${PATH}"
export ATEST_HELPER="${ATEST_HELPER}"
export TF_PATH="${TRADEFED_CLASSPATH}"

if [[ ! -z "${TEST_FILTER_OUTPUT}" ]]; then
  TEST_FILTER=$(<${TEST_FILTER_OUTPUT})
fi

if [[ ! -z "${TEST_FILTER}" ]]; then
  ADDITIONAL_TRADEFED_OPTIONS+=("--atest-include-filter" "${MODULE_NAME}:${TEST_FILTER}")
fi

# Prepend the REMOTE_JAVA_HOME environment variable to the path to ensure
# that all Java invocations throughout the test execution flow use the same
# version.
if [ ! -z "${REMOTE_JAVA_HOME}" ]; then
  export PATH="${REMOTE_JAVA_HOME}/bin:${PATH}"
fi

exit_code_file="$(mktemp /tmp/tf-exec-XXXXXXXXXX)"

"${ATEST_TF_LAUNCHER}" template/atest_local_min \
    --template:map test=atest \
    --template:map reporters="${SCRIPT_DIR}/result-reporters.xml" \
    --tests-dir "$TEST_SRCDIR/__main__/{root_relative_tests_dir}" \
    --logcat-on-failure \
    --no-enable-granular-attempts \
    --no-early-device-release \
    --skip-host-arch-check \
    --include-filter "${MODULE_NAME}" \
    --skip-loading-config-jar \
    "${ADDITIONAL_TRADEFED_OPTIONS[@]}" \
    --bazel-exit-code-result-reporter:file=${exit_code_file} \
    --bazel-xml-result-reporter:file=${XML_OUTPUT_FILE} \
    --log-file-path="${TEST_UNDECLARED_OUTPUTS_DIR}" \
    "$@"

# Use the TF exit code if it terminates abnormally.
tf_exit=$?
if [ ${tf_exit} -ne 0 ]
then
     echo "Tradefed command failed with exit code ${tf_exit}"
     exit ${tf_exit}
fi

# Set the exit code based on the exit code in the reporter-generated file.
exit_code=$(<${exit_code_file})
if [ $? -ne 0 ]
then
  echo "Could not read exit code file: ${exit_code_file}"
  exit 36
fi

if [ ${exit_code} -ne 0 ]
then
  echo "Test failed with exit code ${exit_code}"
  exit ${exit_code}
fi
