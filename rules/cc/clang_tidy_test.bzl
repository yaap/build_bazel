"""
Copyright (C) 2022 The Android Open Source Project

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(":clang_tidy.bzl", "generate_clang_tidy_actions")

_DEFAULT_CHECKS = [
    "android-*",
    "bugprone-*",
    "cert-*",
    "clang-diagnostic-unused-command-line-argument",
    "google-build-explicit-make-pair",
    "google-build-namespaces",
    "google-runtime-operator",
    "google-upgrade-*",
    "misc-*",
    "performance-*",
    "portability-*",
    "-bugprone-assignment-in-if-condition",
    "-bugprone-easily-swappable-parameters",
    "-bugprone-narrowing-conversions",
    "-misc-const-correctness",
    "-misc-no-recursion",
    "-misc-non-private-member-variables-in-classes",
    "-misc-unused-parameters",
    "-performance-no-int-to-ptr",
    "-clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling",
    "-readability-function-cognitive-complexity",
    "-bugprone-reserved-identifier*",
    "-cert-dcl51-cpp",
    "-cert-dcl37-c",
    "-readability-qualified-auto",
    "-bugprone-implicit-widening-of-multiplication-result",
    "-cert-err33-c",
    "-bugprone-unchecked-optional-access",
]
_DEFAULT_CHECKS_AS_ERRORS = [
    "-bugprone-assignment-in-if-condition",
    "-bugprone-branch-clone",
    "-bugprone-signed-char-misuse",
    "-misc-const-correctness",
]

def _clang_tidy_impl(ctx):
    tidy_outs = generate_clang_tidy_actions(
        ctx,
        ctx.attr.copts,
        ctx.attr.deps,
        ctx.files.srcs,
        ctx.files.hdrs,
        ctx.attr.language,
        ctx.attr.tidy_flags,
        ctx.attr.tidy_checks,
        ctx.attr.tidy_checks_as_errors,
        ctx.attr.tidy_timeout_srcs,
    )
    return [
        DefaultInfo(files = depset(tidy_outs)),
    ]

_clang_tidy = rule(
    implementation = _clang_tidy_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "copts": attr.string_list(),
        "hdrs": attr.label_list(allow_files = True),
        "language": attr.string(values = ["c++", "c"], default = "c++"),
        "tidy_checks": attr.string_list(),
        "tidy_checks_as_errors": attr.string_list(),
        "tidy_flags": attr.string_list(),
        "tidy_timeout_srcs": attr.label_list(allow_files = True),
        "_clang_tidy_sh": attr.label(
            default = Label("@//prebuilts/clang/host/linux-x86:clang-tidy.sh"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "The clang tidy shell wrapper",
        ),
        "_clang_tidy": attr.label(
            default = Label("@//prebuilts/clang/host/linux-x86:clang-tidy"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "The clang tidy executable",
        ),
        "_clang_tidy_real": attr.label(
            default = Label("@//prebuilts/clang/host/linux-x86:clang-tidy.real"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "_with_tidy": attr.label(
            default = "//build/bazel/flags/cc/tidy:with_tidy",
        ),
        "_allow_local_tidy_true": attr.label(
            default = "//build/bazel/flags/cc/tidy:allow_local_tidy_true",
        ),
        "_with_tidy_flags": attr.label(
            default = "//build/bazel/flags/cc/tidy:with_tidy_flags",
        ),
        "_default_tidy_header_dirs": attr.label(
            default = "//build/bazel/flags/cc/tidy:default_tidy_header_dirs",
        ),
        "_tidy_timeout": attr.label(
            default = "//build/bazel/flags/cc/tidy:tidy_timeout",
        ),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)

def _get_arg(env, actions, argname):
    arg = None
    for a in actions[0].argv:
        if a.startswith(argname):
            arg = a[len(argname):]
            break
    asserts.false(env, arg == None, "could not find `{}` argument".format(argname))
    return arg

def _checks_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)

    checks = _get_arg(env, actions, "-checks=").split(",")
    asserts.set_equals(env, sets.make(ctx.attr.expected_checks), sets.make(checks))

    checks_as_errors = _get_arg(env, actions, "-warnings-as-errors=").split(",")
    asserts.set_equals(env, sets.make(ctx.attr.expected_checks_as_errors), sets.make(checks_as_errors))

    return analysistest.end(env)

_checks_test = analysistest.make(
    _checks_test_impl,
    attrs = {
        "expected_checks": attr.string_list(mandatory = True),
        "expected_checks_as_errors": attr.string_list(mandatory = True),
    },
)

def _test_checks():
    name = "checks"
    test_name = name + "test"

    _clang_tidy(
        name = name,
        srcs = ["a.cpp"],
        tags = ["manual"],
    )

    _checks_test(
        name = test_name,
        target_under_test = name,
        expected_checks = _DEFAULT_CHECKS,
        expected_checks_as_errors = _DEFAULT_CHECKS_AS_ERRORS,
    )

    return [
        test_name,
    ]

def clang_tidy_test_suite(name):
    native.test_suite(
        name = name,
        tests = _test_checks(),
    )
