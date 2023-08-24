# Copyright (C) 2023 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("//build/bazel/rules/tradefed:tradefed.bzl", "TEST_DEP_SUFFIX", "tradefed_test_suite")

def sh_test(
        name,
        srcs,
        data = [],
        tags = [],
        test_config = None,
        test_config_template = None,
        auto_gen_config = True,
        template_install_base = None,
        template_configs = [],
        visibility = None,
        **kwargs):
    "Bazel macro to correspond with the sh_test Soong module."

    test_dep_name = name + TEST_DEP_SUFFIX
    native.sh_test(
        name = test_dep_name,
        srcs = srcs,
        data = data,
        tags = tags + ["manual"],
        **kwargs
    )

    tradefed_test_suite(
        name = name,
        test_dep = test_dep_name,
        # TODO(b/296964806): Handle auto_gen_config in tradefed Bazel rules.
        test_config = test_config,
        template_configs = template_configs,
        template_test_config = test_config_template,
        template_install_base = template_install_base,
        device_driven_test_config = "//build/make/core:native_test_config_template.xml",
        tags = tags,
        visibility = visibility,
    )
