# This repository provides files that Soong emits during bp2build (other than
# converted BUILD files), mostly .bzl files containing constants to support the
# converted BUILD files.
load("//build/bazel/rules:soong_injection.bzl", "soong_injection_repository")
soong_injection_repository(name="soong_injection")

# ! WARNING ! WARNING ! WARNING !
# make_injection is a repository rule to allow Bazel builds to depend on
# Soong-built prebuilts for experimental purposes. It is fragile, slow, and
# works for very limited use cases. Do not add a dependency that will cause
# make_injection to run for any prod builds or tests.
#
# If you need to add something in this list, please contact the Roboleaf
# team and ask jingwen@ for a review.
load("//build/bazel/rules:make_injection.bzl", "make_injection_repository")
make_injection_repository(
    name = "make_injection",
    target_module_files = {},
    watch_android_bp_files = [],
)
# ! WARNING ! WARNING ! WARNING !

local_repository(
    name = "rules_cc",
    path = "build/bazel/rules_cc",
)

local_repository(
    name = "bazel_skylib",
    path = "external/bazel-skylib",
)

load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")

bazel_skylib_workspace()

local_repository(
    name = "rules_android",
    path = "external/bazelbuild-rules_android",
)

register_toolchains(
  "//prebuilts/build-tools:py_toolchain",
  "//prebuilts/clang/host/linux-x86:all",

  # For Starlark Android rules
  "//prebuilts/sdk:android_default_toolchain",
  "//prebuilts/sdk:android_sdk_tools",

  # For native android_binary
  "//prebuilts/sdk:android_sdk_tools_for_native_android_binary",

  # For APEX rules
  "//build/bazel/rules/apex:all",
)

bind(
  name = "databinding_annotation_processor",
  actual = "//prebuilts/sdk:compiler_annotation_processor",
)

bind(
  name = "android/dx_jar_import",
  actual = "//prebuilts/sdk:dx_jar_import",
)

# The r8.jar in prebuilts/r8 happens to have the d8 classes needed
# for Android app building, whereas the d8.jar in prebuilts/sdk/tools doesn't.
bind(
  name = "android/d8_jar_import",
  actual = "//prebuilts/r8:r8_jar_import",
)

# TODO(b/201242197): Avoid downloading remote_coverage_tools (on CI) by creating
# a stub workspace. Test rules (e.g. sh_test) depend on this external dep, but
# we don't support coverage yet. Either vendor the external dep into AOSP, or
# cut the dependency from test rules to the external repo.
local_repository(
    name = "remote_coverage_tools",
    path = "build/bazel/rules/coverage/remote_coverage_tools",
)
