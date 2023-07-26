# Copyright (C) 2022 The Android Open Source Project
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

"""cc_test macro for building native tests with Bazel."""

load("//build/bazel/rules/tradefed:tradefed.bzl", "LANGUAGE_CC", "TEST_DEP_SUFFIX", "tradefed_test_suite")
load(":cc_binary.bzl", "cc_binary")

# TODO(b/244559183): Keep this in sync with cc/test.go#linkerFlags
_gtest_copts = select({
    "//build/bazel/platforms/os:linux_glibc": ["-DGTEST_OS_LINUX"],
    "//build/bazel/platforms/os:darwin": ["-DGTEST_OS_MAC"],
    "//build/bazel/platforms/os:windows": ["-DGTEST_OS_WINDOWS"],
    "//conditions:default": ["-DGTEST_OS_LINUX_ANDROID"],
}) + select({
    "//build/bazel/platforms/os:android": [],
    "//conditions:default": ["-O0", "-g"],  # here, default == host platform
}) + [
    "-DGTEST_HAS_STD_STRING",
    "-Wno-unused-result",  # TODO(b/244433518): Figure out why this is necessary in the bazel compile action.
]

def cc_test(
        name,
        copts = [],
        deps = [],
        dynamic_deps = [],
        gtest = True,
        isolated = True,  # TODO(b/244432609): currently no-op. @unused
        tags = [],
        tidy = None,
        tidy_checks = None,
        tidy_checks_as_errors = None,
        tidy_flags = None,
        tidy_disabled_srcs = None,
        tidy_timeout_srcs = None,
        test_config = None,
        template_test_config = None,
        template_configs = [],
        template_install_base = None,
        visibility = None,
        target_compatible_with = None,
        **kwargs):
    # NOTE: Keep this in sync with cc/test.go#linkerDeps
    if gtest:
        # TODO(b/244433197): handle ctx.useSdk() && ctx.Device() case to link against the ndk variants of the gtest libs.
        # TODO(b/244432609): handle isolated = True to link against libgtest_isolated_main and liblog (dynamically)
        copts = copts + _gtest_copts

    # A cc_test is essentially the same as a cc_binary. Let's reuse the
    # implementation for now and factor the common bits out as necessary.
    test_dep_name = name + TEST_DEP_SUFFIX
    cc_binary(
        name = test_dep_name,
        copts = copts,
        deps = deps,
        dynamic_deps = dynamic_deps,
        generate_cc_test = True,
        tidy = tidy,
        tidy_checks = tidy_checks,
        tidy_checks_as_errors = tidy_checks_as_errors,
        tidy_flags = tidy_flags,
        tidy_disabled_srcs = tidy_disabled_srcs,
        tidy_timeout_srcs = tidy_timeout_srcs,
        tags = tags + ["manual"],
        target_compatible_with = target_compatible_with,
        visibility = visibility,
        **kwargs
    )

    tradefed_test_suite(
        name = name,
        test_dep = test_dep_name,
        test_config = test_config,
        template_configs = template_configs,
        template_install_base = template_install_base,
        deviceless_test_config = "//build/make/core:native_host_test_config_template.xml",
        device_driven_test_config = "//build/make/core:native_test_config_template.xml",
        tags = tags,
        visibility = visibility,
        test_language = LANGUAGE_CC,
    )
