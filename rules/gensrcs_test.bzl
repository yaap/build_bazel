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

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("//build/bazel/rules:gensrcs.bzl", "gensrcs")

INPUT_FILES = [
    "src1.txt",
    "src2.txt",
]

OUTPUT_EXTENSION = "out"

# ==== Check the actions created by gensrcs ====

def _test_actions_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)

    # Expect an action for each pair of input/output file
    asserts.equals(env, expected = 2, actual = len(actions))

    # Check name for input and output files for each action
    for i in range(len(actions)):
        action = actions[i]
        input_file = action.inputs.to_list()[0]
        expected_input_file = INPUT_FILES[i]

        asserts.equals(
            env,
            expected = expected_input_file,
            actual = input_file.basename,
        )
        asserts.equals(
            env,
            expected = expected_input_file.rstrip(".txt") + "." + OUTPUT_EXTENSION,
            actual = action.outputs.to_list()[0].basename,
        )

    return analysistest.end(env)

actions_test = analysistest.make(_test_actions_impl)

def _test_actions():
    name = "actions"
    test_name = name + "_test"
    # Rule under test
    gensrcs(
        name = name,
        cmd = "cat $(SRC) > $(OUT)",
        srcs = INPUT_FILES,
        output_extension = OUTPUT_EXTENSION,
        tags = ["manual"],  # make sure it's not built using `:all`
    )

    actions_test(
        name = test_name,
        target_under_test = name,
    )
    return test_name

# ==== Check the output file when out_extension is unset ====

def _test_unset_output_extension_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)
    asserts.equals(env, expected = 1, actual = len(actions))
    print(actions)
    action = actions[0]
    asserts.equals(
        env,
        expected = "input.",
        actual = action.outputs.to_list()[0].basename,
    )

    return analysistest.end(env)

unset_output_extension_test = analysistest.make(_test_unset_output_extension_impl)

def _test_unset_output_extension():
    name = "unset_output_extension"
    test_name = name + "_test"
    # Rule under test
    gensrcs(
        name = "TSTSS",
        cmd = "cat $(SRC) > $(OUT)",
        srcs = ["input.txt"],
        tags = ["manual"],  # make sure it's not built using `:all`
    )

    unset_output_extension_test(
        name = test_name,
        target_under_test = "TSTSS",
    )
    return test_name

def gensrcs_tests_suite(name):
    """Creates test targets for gensrcs.bzl"""
    native.test_suite(
        name = name,
        tests = [
            _test_actions(),
            _test_unset_output_extension(),
        ],
    )
