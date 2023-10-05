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

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_testing//lib:analysis_test.bzl", rt_analysis_test = "analysis_test", rt_test_suite = "test_suite")
load("@rules_testing//lib:truth.bzl", "matching", "subjects")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//build/bazel/rules/java:java_resources.bzl", "java_resources")
load(":library.bzl", "java_library")

ActionArgsInfo = provider(
    fields = {
        "argv_map": "A dict with compile action arguments keyed by the target label",
    },
)

def _library_compile_actions_aspect_impl(target, ctx):
    argv_map = {}
    if ctx.rule.kind == "java_library_sdk_transition":
        if len(ctx.rule.attr.exports) > 1:
            fail("multiple exports is not supported.")
        for export in ctx.rule.attr.exports:
            label_name = export.label.name
            action = export[ActionArgsInfo].argv_map.get(label_name, None)
            if action:
                argv_map[target.label.name] = action
    else:
        argv = []
        for action in target.actions:
            if action.mnemonic == "Javac":
                argv.extend(action.argv)
        argv_map[target.label.name] = argv

    return ActionArgsInfo(
        argv_map = argv_map,
    )

library_compile_actions_aspect = aspect(
    implementation = _library_compile_actions_aspect_impl,
    attr_aspects = ["exports"],
)

def _compile_test_impl(ctx):
    env = analysistest.begin(ctx)
    if len(ctx.attr.args_to_check) == 0:
        return analysistest.end(env)
    target = analysistest.target_under_test(env)
    argv = target[ActionArgsInfo].argv_map[target.label.name]
    expected_args = ctx.attr.args_to_check
    first_arg = expected_args[0]
    for (i, arg) in enumerate(argv):
        if arg == first_arg:
            asserts.true(env, len(argv) >= i + len(expected_args), "expected enough at least %d args based on # of expected args (%d), got %d" % (i + len(expected_args), len(expected_args), len(argv)))
            asserts.equals(env, expected_args, argv[i:i + len(expected_args)])
            break
    return analysistest.end(env)

java_library_compile_test = analysistest.make(
    _compile_test_impl,
    attrs = {
        "args_to_check": attr.string_list(),
    },
    extra_target_under_test_aspects = [library_compile_actions_aspect],
)

def _host_java_library_has_correct_java_version():
    basename = "host_java_library_has_correct_java_version"
    test_name = basename + "_test"

    java_library(
        name = basename,
        srcs = ["foo.java"],
        sdk_version = "21",
        java_version = "1.7",
        tags = ["manual"],
    )

    java_library_compile_test(
        name = test_name,
        target_under_test = basename,
        args_to_check = [
            "-source",
            "7",
            "-target",
            "7",
        ],
    )

    return test_name

def _test_java_library_additional_resources_impl(env, target):
    deps = env.expect.that_target(target).attr("deps", factory = subjects.collection)
    target_name = target.label.name.removesuffix("_private")

    expected_dep_name = target_name + "__additional_resources"

    deps.contains_predicate(
        matching.custom(
            desc = expected_dep_name,
            func = lambda dep: dep.label == Label(expected_dep_name),
        ),
    )

def _test_java_library_additional_resources(name):
    macro_wrapper_name = name + "_library_target"
    java_resource_target_name = name + "java_res_target"
    rt_util.helper_target(
        java_library,
        name = macro_wrapper_name,
        srcs = ["foo.java"],
        additional_resources = [java_resource_target_name],
    )

    rt_util.helper_target(
        java_resources,
        name = java_resource_target_name,
        resources = ["res1.java"],
    )

    rt_analysis_test(
        name = name,
        impl = _test_java_library_additional_resources_impl,
        # want to test the java_library target created by the java_library macro
        target = macro_wrapper_name + "_private",
    )

def java_library_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            _host_java_library_has_correct_java_version(),
        ],
    )

def rt_java_library_test_suite(name):
    rt_test_suite(
        name = name,
        tests = [
            _test_java_library_additional_resources,
        ],
    )
