# Copyright (C) 2022 The Android Open Source Project
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

load("//build/bazel/rules/android:android_app_certificate.bzl", "android_app_certificate")
load("//build/bazel/rules:sh_binary.bzl", "sh_binary")
load("//build/bazel/rules/cc:cc_binary.bzl", "cc_binary")
load("//build/bazel/rules/cc:cc_library_shared.bzl", "cc_library_shared")
load("//build/bazel/rules:prebuilt_file.bzl", "prebuilt_file")
load(":apex.bzl", "apex")
load(":apex_key.bzl", "apex_key")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _canned_fs_config_test(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)

    found_canned_fs_config_action = False

    for a in actions:
        if a.mnemonic != "FileWrite":
            # The canned_fs_config uses ctx.actions.write.
            continue

        outputs = a.outputs.to_list()
        if len(outputs) != 1:
            continue
        if not outputs[0].basename.endswith("_canned_fs_config.txt"):
            continue

        actual_entries = sorted(a.content.split("\n"))
        expected_entries = sorted(ctx.attr.expected_entries)
        asserts.equals(env, expected_entries, actual_entries)

        found_canned_fs_config_action = True
        break

    # Ensures that we actually found the canned_fs_config.txt generation action.
    asserts.true(env, found_canned_fs_config_action)

    return analysistest.end(env)

canned_fs_config_test = analysistest.make(
    _canned_fs_config_test,
    attrs = {
        "expected_entries": attr.string_list(
            doc = "Expected lines in the canned_fs_config.txt",
        ),
    },
)

# Set up test-local dependencies required for every apex.
def setup_apex_required_deps(name):
    file_contexts_name = name + "_file_contexts"
    manifest_name = name + "_manifest"
    key_name = name + "_key"
    certificate_name = name + "_certificate"

    native.genrule(
        name = file_contexts_name,
        outs = [file_contexts_name + ".out"],
        cmd = "echo unused && exit 1",
        tags = ["manual"],
    )

    native.genrule(
        name = manifest_name,
        outs = [manifest_name + ".json"],
        cmd = "echo unused && exit 1",
        tags = ["manual"],
    )

    # Required for ApexKeyInfo provider
    apex_key(
        name = key_name,
        private_key = key_name + ".pem",
        public_key = key_name + ".avbpubkey",
        tags = ["manual"],
    )

    # Required for AndroidAppCertificate provider
    android_app_certificate(
        name = certificate_name,
        certificate = certificate_name + ".cert",
        tags = ["manual"],
    )

    return struct(
        file_contexts_name = file_contexts_name,
        manifest_name = manifest_name,
        key_name = key_name,
        certificate_name = certificate_name,
    )

def test_apex(
    name,
    file_contexts = None,
    key = None,
    manifest = None,
    certificate = None,
    **kwargs):

    names = setup_apex_required_deps(name)
    apex(
        name = name,
        file_contexts = file_contexts or names.file_contexts_name,
        key = key or names.key_name,
        manifest = manifest or names.manifest_name,
        certificate = certificate or names.certificate_name,
        tags = ["manual"],
        **kwargs,
    )


def _test_canned_fs_config_basic():
    name = "apex_canned_fs_config_basic"
    test_name = name + "_test"

    test_apex(name = name)

    canned_fs_config_test(
        name = test_name,
        target_under_test = name,
        expected_entries = [
            "/ 0 2000 0755",
            "/apex_manifest.json 1000 1000 0644",
            "/apex_manifest.pb 1000 1000 0644",
        ],
    )

    return test_name

def _test_canned_fs_config_binaries():
    name = "apex_canned_fs_config_binaries"
    test_name = name + "_test"

    sh_binary(
        name = "bin_sh",
        srcs = ["bin.sh"],
        tags = ["manual"],
    )

    cc_binary(
        name = "bin_cc",
        srcs = ["bin.cc"],
        tags = ["manual"],
    )

    test_apex(
        name = name,
        binaries = ["bin_sh", "bin_cc"],
    )

    canned_fs_config_test(
        name = test_name,
        target_under_test = name,
        expected_entries = [
            "/ 0 2000 0755",
            "/apex_manifest.json 1000 1000 0644",
            "/apex_manifest.pb 1000 1000 0644",
            "/bin 0 2000 0755",
            "/bin/bin_cc 0 2000 0755",
            "/bin/bin_sh 0 2000 0755",
        ],
    )

    return test_name

def _test_canned_fs_config_native_shared_libs_arm():
    name = "apex_canned_fs_config_native_shared_libs_arm"
    test_name = name + "_test"

    cc_library_shared(
        name = name + "_lib_cc",
        srcs = [name + "_lib.cc"],
        tags = ["manual"],
    )

    cc_library_shared(
        name = name + "_lib2_cc",
        srcs = [name + "_lib2.cc"],
        tags = ["manual"],
    )

    test_apex(
        name = name,
        native_shared_libs_32 = [name + "_lib_cc"],
        native_shared_libs_64 = [name + "_lib2_cc"],
    )

    canned_fs_config_test(
        name = test_name,
        target_under_test = name,
        expected_entries = [
            "/ 0 2000 0755",
            "/apex_manifest.json 1000 1000 0644",
            "/apex_manifest.pb 1000 1000 0644",
            "/lib 0 2000 0755",
            "/lib/apex_canned_fs_config_native_shared_libs_arm_lib_cc.so 1000 1000 0644",
            "/lib/libc++.so 1000 1000 0644",
        ],
        target_compatible_with = ["//build/bazel/platforms/arch:arm"],
    )

    return test_name

def _test_canned_fs_config_native_shared_libs_arm64():
    name = "apex_canned_fs_config_native_shared_libs_arm64"
    test_name = name + "_test"

    cc_library_shared(
        name = name + "_lib_cc",
        srcs = [name + "_lib.cc"],
        tags = ["manual"],
    )

    cc_library_shared(
        name = name + "_lib2_cc",
        srcs = [name + "_lib2.cc"],
        tags = ["manual"],
    )

    test_apex(
        name = name,
        native_shared_libs_32 = [name + "_lib_cc"],
        native_shared_libs_64 = [name + "_lib2_cc"],
    )

    canned_fs_config_test(
        name = test_name,
        target_under_test = name,
        expected_entries = [
            "/ 0 2000 0755",
            "/apex_manifest.json 1000 1000 0644",
            "/apex_manifest.pb 1000 1000 0644",
            "/lib 0 2000 0755",
            "/lib/apex_canned_fs_config_native_shared_libs_arm64_lib_cc.so 1000 1000 0644",
            "/lib/libc++.so 1000 1000 0644",
            "/lib64 0 2000 0755",
            "/lib64/apex_canned_fs_config_native_shared_libs_arm64_lib2_cc.so 1000 1000 0644",
            "/lib64/libc++.so 1000 1000 0644",
        ],
        target_compatible_with = ["//build/bazel/platforms/arch:arm64"],
    )

    return test_name

def _test_canned_fs_config_prebuilts():
    name = "apex_canned_fs_config_prebuilts"
    test_name = name + "_test"

    prebuilt_file(
        name = "file",
        src = "file.txt",
        dir = "etc",
        tags = ["manual"],
    )

    prebuilt_file(
        name = "nested_file_in_dir",
        src = "file2.txt",
        dir = "etc/nested",
        tags = ["manual"],
    )

    prebuilt_file(
        name = "renamed_file_in_dir",
        src = "file3.txt",
        dir = "etc",
        filename = "renamed_file3.txt",
        tags = ["manual"],
    )

    test_apex(
        name = name,
        prebuilts = [
            ":file",
            ":nested_file_in_dir",
            ":renamed_file_in_dir",
        ],
    )

    canned_fs_config_test(
        name = test_name,
        target_under_test = name,
        expected_entries = [
            "/ 0 2000 0755",
            "/apex_manifest.json 1000 1000 0644",
            "/apex_manifest.pb 1000 1000 0644",
            "/etc 0 2000 0755",
            "/etc/file 1000 1000 0644",
            "/etc/nested 0 2000 0755",
            "/etc/nested/nested_file_in_dir 1000 1000 0644",
            "/etc/renamed_file3.txt 1000 1000 0644",
        ],
    )

    return test_name

def apex_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            _test_canned_fs_config_basic(),
            _test_canned_fs_config_binaries(),
            _test_canned_fs_config_native_shared_libs_arm(),
            _test_canned_fs_config_native_shared_libs_arm64(),
            _test_canned_fs_config_prebuilts(),
        ],
    )
