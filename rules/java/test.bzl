# Copyright (C) 2023 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@rules_java//java:defs.bzl", "java_binary")
load("//build/bazel/rules/tradefed:tradefed.bzl", "LANGUAGE_JAVA", "TEST_DEP_SUFFIX", "tradefed_test_suite")

HOST_TEST_TEMPLATE = "//build/make/core:java_host_unit_test_config_template.xml"

def java_test(
        name = "",
        srcs = [],
        deps = [],
        tags = [],
        visibility = None,
        target_compatible_with = [],
        **kwargs):
    test_dep_name = name + TEST_DEP_SUFFIX
    java_binary_name = name + "_jb"

    # tradefed_test_suite uses the _deploy.jar from this java_binary to execute tests.
    java_binary(
        name = java_binary_name,
        srcs = srcs,
        deps = deps,
        create_executable = False,
        tags = tags + ["manual"],
        visibility = visibility,
        target_compatible_with = target_compatible_with,
        **kwargs
    )

    native.filegroup(
        name = test_dep_name,
        srcs = [java_binary_name + "_deploy.jar"],
    )

    tradefed_test_suite(
        name = name,
        test_dep = test_dep_name,
        test_config = None,
        template_test_config = None,
        template_configs = None,
        template_install_base = None,
        tags = tags,
        test_language = LANGUAGE_JAVA,
        visibility = visibility,
        deviceless_test_config = HOST_TEST_TEMPLATE,
    )
