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

"""The tradefest test ruleset.

This file contains the definition and implementation of:

- tradefed_test_suite, which expands to
    - tradefed_deviceless_test
    - tradefed_host_driven_device_test
    - tradefed_device_driven_test

These rules provide Tradefed harness support around test executables and
runfiles. They are language independent, and thus work with cc_test, java_test,
and other test types.

The execution mode (host, device, deviceless) is automatically determined by the
target_compatible_with attribute of the test dependency. Whether a test runs is
handled by Bazel's incompatible target skipping, i.e. a test dep that's
compatible only with android would cause the tradefed_deviceless_test to be
SKIPPED automatically.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")

# Apply this suffix to the name of the test dep target (e.g. the cc_test target)
TEST_DEP_SUFFIX = "__tf_internal"

LANGUAGE_CC = "cc"
LANGUAGE_JAVA = "java"

# A transition to force the target device platforms configuration. This is
# used in the tradefed -> cc_test edge (for example).
#
# TODO(b/290716628): Handle multilib. For example, cc_test sets `multilib:
# "both"` by default, so this may drop the secondary arch of the test, depending
# on the TARGET_PRODUCT.
def _tradefed_always_device_transition_impl(settings, _):
    old_platform = str(settings["//command_line_option:platforms"][0])

    # TODO(b/290716626): This is brittle handling for distinguishing between
    # device / not-device of the current target platform. Could use better
    # helpers.
    new_platform = old_platform.removesuffix("_linux_x86_64")
    return {
        "//command_line_option:platforms": new_platform,
    }

_tradefed_always_device_transition = transition(
    implementation = _tradefed_always_device_transition_impl,
    inputs = ["//command_line_option:platforms"],
    outputs = ["//command_line_option:platforms"],
)

_TRADEFED_TEST_ATTRIBUTES = {
    "_tradefed_test_sh_template": attr.label(
        default = ":tradefed.sh.tpl",
        allow_single_file = True,
        doc = "Template script to launch tradefed.",
    ),
    "_atest_tradefed_launcher": attr.label(
        default = "//tools/asuite/atest:atest_tradefed.sh",
        allow_single_file = True,
        cfg = "exec",
    ),
    "_atest_helper": attr.label(
        default = "//tools/asuite/atest:atest_script_help.sh",
        allow_single_file = True,
        cfg = "exec",
    ),
    "_tradefed_dependencies": attr.label_list(
        default = [
            "//prebuilts/runtime:prebuilt-runtime-adb",
            "//tools/tradefederation/prebuilts/filegroups/tradefed:bp2build_all_srcs",
            "//tools/tradefederation/prebuilts/filegroups/suite:compatibility-host-util-prebuilt",
            "//tools/tradefederation/prebuilts/filegroups/suite:compatibility-tradefed-prebuilt",
            "//tools/asuite/atest:atest-tradefed",
            "//tools/asuite/atest/bazel/reporter:bazel-result-reporter",
        ],
        doc = "Files needed on the PATH to run tradefed",
        cfg = "exec",
    ),
    "test_config": attr.label(
        allow_single_file = True,
        doc = "Test/Tradefed config.",
    ),
    "template_test_config": attr.label(
        allow_single_file = True,
        doc = "Template to generate test config.",
    ),
    "template_configs": attr.string_list(
        doc = "Extra tradefed config options to extend into generated test config.",
    ),
    "template_install_base": attr.string(
        default = "/data/local/tmp",
        doc = "Directory to install tests onto the device for generated config",
    ),
    "test_language": attr.string(
        default = "",
        values = ["", LANGUAGE_CC, LANGUAGE_JAVA],
        doc = "the programming language the test uses",
    ),
}

# The normalized name of test under tradefed harness. This is without any of the
#
# "__tf" suffixes, e.g. adbd_test or hello_world_test.
#
#The normalized module name is used as the stem for the test executable or
# config files, which are referenced in AndroidTest.xml, like in PushFilePreparer elements.
def _normalize_test_name(s):
    return s.replace(TEST_DEP_SUFFIX, "")

# Get test config if specified or generate test config from template.
def _get_or_generate_test_config(ctx, tf_test_dir, test_executable, test_language):
    # Validate input
    total = 0
    if ctx.file.test_config:
        total += 1
    if ctx.file.template_test_config:
        total += 1
    if total != 1:
        fail("Exactly one of test_config or test_config_template should be provided, but got: " +
             "%s %s" % (ctx.file.test_config, ctx.file.template_test_config))

    basename = _normalize_test_name(test_executable.basename)

    # If existing tradefed config is specified, symlink to it and return early.
    #
    # The config needs to be a sibling file to the test executable, and both
    # files must be in tf_test_dir. Given that ctx.file.test_config could be
    # from another package, like //build/make/core, this symlink handles that.
    #
    # $ tree bazel-bin/packages/modules/adb/adb_test__tf_deviceless_test/testcases/
    # bazel-bin/packages/modules/adb/adb_test__tf_deviceless_test/testcases/
    # ├── adb_test -> /out/bazel/output_user_root/7f5b7a0603f97e18eafe9111781920be/execroot/__main__/bazel-out/aosp_cf_x86_64_phone-userdebug_linux_x86_64-opt-ST-0f3d6a823fdb/bin/packages/modules/adb/bin/adb_test/adb_test
    # └── adb_test.config
    out = ctx.actions.declare_file(paths.join(tf_test_dir, basename + ".config"))
    if ctx.file.test_config:
        ctx.actions.symlink(
            output = out,
            target_file = ctx.file.test_config,
        )
        return out

    # No test config specified, generate config from template. Join extra
    # configs together and add xml spacing indent.
    if test_language == LANGUAGE_JAVA:
        # rm ".jar" extension since it's "{MODULE}.jar" in Java config template
        basename = basename.removesuffix(".jar")
    ctx.actions.expand_template(
        template = ctx.file.template_test_config,
        output = out,
        substitutions = {
            "{MODULE}": basename,
            "{EXTRA_CONFIGS}": "\n    ".join(ctx.attr.template_configs),
            "{TEST_INSTALL_BASE}": ctx.attr.template_install_base,
        },
    )
    return out

# Generate tradefed result reporter config.
def _create_result_reporter_config(ctx):
    result_reporters_config_file = ctx.actions.declare_file("result-reporters.xml")
    config_lines = [
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
        "<configuration>",
    ]

    result_reporters = [
        "com.android.tradefed.result.BazelExitCodeResultReporter",
        "com.android.tradefed.result.BazelXmlResultReporter",
        "com.android.tradefed.result.proto.FileProtoResultReporter",
    ]
    for result_reporter in result_reporters:
        config_lines.append("    <result_reporter class=\"%s\" />" % result_reporter)
    config_lines.append("</configuration>")

    ctx.actions.write(result_reporters_config_file, "\n".join(config_lines))
    return result_reporters_config_file

# Get the test Target object.
#
# ctx.attr.test could be a list, depending on the rule configuration. Host
# driven device test transitions ctx.attr.test to device config, which turns the
# test attr into a label list.
def _get_test_target(ctx):
    if type(ctx.attr.test) == "list":
        return ctx.attr.test[0]
    return ctx.attr.test

# Generate and run tradefed bash script entry point and associated runfiles.
def _tradefed_test_impl(ctx, tradefed_options = []):
    tf_test_dir = ctx.label.name + "/testcases"

    test_target = _get_test_target(ctx)
    test_language = ctx.attr.test_language

    # For Java, a library may make more sense here than the executable. When
    # expanding tradefed_test_impl to accept more rule types, this could be
    # turned into a provider, whether set by the rule or an aspect visiting the
    # rule.
    if test_language == LANGUAGE_JAVA:
        test_executable = test_target.files.to_list()[0]
    else:
        test_executable = test_target.files_to_run.executable
    test_basename = _normalize_test_name(test_executable.basename)

    # Get or generate test config.
    test_config = _get_or_generate_test_config(ctx, tf_test_dir, test_executable, test_language)

    # Generate result reporter config file.
    report_config = _create_result_reporter_config(ctx)

    test_runfiles = []

    out = ctx.actions.declare_file(test_basename, sibling = test_config)

    # Symlink the test executable to the test cases directory
    ctx.actions.symlink(output = out, target_file = test_executable)

    root_relative_tests_dir = paths.dirname(out.short_path)
    test_runfiles.append(out)

    # Prepare test-provided runfiles
    for f in test_target.files.to_list():
        if f == test_executable:
            continue
        test_runfiles.append(f)

    # Prepare tooling runfiles.
    # Symlink tradefed dependencies to the root of the test package.
    for f in ctx.files._tradefed_dependencies:
        out = ctx.actions.declare_file(f.basename)
        ctx.actions.symlink(
            output = out,
            target_file = f,
        )
        test_runfiles.append(out)
        test_runfiles.append(f)

    # Gather runfiles.
    runfiles = ctx.runfiles(
        files = test_runfiles + [
            test_config,
            report_config,
            ctx.file._atest_tradefed_launcher,
            ctx.file._atest_helper,
        ],
    )
    runfiles = runfiles.merge(test_target.default_runfiles)

    # Generate script to run tradefed.
    script = ctx.actions.declare_file("%s.sh" % ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._tradefed_test_sh_template,
        output = script,
        is_executable = True,
        substitutions = {
            "{MODULE}": test_basename,
            "{atest_tradefed_launcher}": _abspath(ctx.file._atest_tradefed_launcher.short_path),
            "{atest_helper}": _abspath(ctx.file._atest_helper.short_path),
            "{tradefed_classpath}": _classpath(ctx.files._tradefed_dependencies),
            "{root_relative_tests_dir}": root_relative_tests_dir,
            "{additional_tradefed_options}": " ".join(tradefed_options),
        },
    )

    return [DefaultInfo(
        executable = script,
        runfiles = runfiles,
    )]

def _tradefed_deviceless_test_impl(ctx):
    return _tradefed_test_impl(
        ctx,
        tradefed_options = [
            "--null-device",  # don't allocate a device
        ],
    )

tradefed_deviceless_test = rule(
    attrs = dicts.add(_TRADEFED_TEST_ATTRIBUTES, {
        "test": attr.label(
            # Deviceless test executables should always build for host.
            doc = "Test target to run in tradefed.",
        ),
    }),
    test = True,
    implementation = _tradefed_deviceless_test_impl,
    doc = """A rule used to run host deviceless tests using Tradefed.

Generally tests that use one of the following runners (not exhaustive):

- com.android.compatibility.common.tradefed.testtype.JarHostTest (java_test_host).
- com.android.tradefed.testtype.HostTest
- com.android.tradefed.testtype.HostGTest (cc_test_host)
- com.android.tradefed.testtype.python.PythonBinaryHostTest

These are tests built and executed on the host, and do NOT need a
connected device to run.
""",
)

tradefed_device_driven_test = rule(
    attrs = dicts.add(_TRADEFED_TEST_ATTRIBUTES, {
        "test": attr.label(
            # Device driven tests should always build for device.
            cfg = _tradefed_always_device_transition,
            doc = "Test target to run in tradefed.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    }),
    test = True,
    implementation = _tradefed_test_impl,
    doc = """A rule used to run device-driven tests using Tradefed

Generally tests that use one of the following runners (not exhaustive):

- com.android.tradefed.testtype.AndroidJUnitTest (android instrumentation test).
- com.android.tradefed.testtype.GTest (native device tests)
- com.android.compatibility.testtype.LibcoreTest
- com.android.compatibility.testtype.DalvikTest
- com.android.compatibility.tradefed.CtsRootTradefedTest

This results in a single tradefed invocation for a device driven test that uses
plugins like SuiteApkInstaller. Tradefed is still executed on the host,
but the test is driven entirely on the device.""",
)

tradefed_host_driven_device_test = rule(
    attrs = dicts.add(_TRADEFED_TEST_ATTRIBUTES, {
        "test": attr.label(
            # Host driven device tests should always build for the host by
            # default (since they're host driven!). There may be dependencies
            # from the test to other runtime deps which the host executable will
            # push onto the device during test runtime, but we'll let the test
            # itself handle the configuration transition to those dependencies.
            doc = "Test target to run in tradefed.",
        ),
    }),
    test = True,
    implementation = _tradefed_test_impl,
    doc = """A rule used to run host-driven device tests using Tradefed

Generally tests that use one of the following runners (not exhaustive):

- com.android.compatibility.common.tradefed.testtype.JarHostTest (java_test_host).
- com.android.tradefed.testtype.HostTest
- com.android.tradefed.testtype.HostGTest (cc_test_host)
- com.android.tradefed.testtype.mobly.MoblyBinaryHostTest
- com.android.tradefed.testtype.python.PythonBinaryHostTest

These are tests built and executed on the host, but may rely on Tradefed
plugins to install data onto the device during the test, like
PushFilePreparer or SuiteApkInstaller.
""",
)

def tradefed_test_suite(
        name,
        test_dep,
        test_config,
        template_configs,
        template_install_base,
        tags,
        visibility,
        test_language = "",
        deviceless_test_config = None,
        device_driven_test_config = None,
        host_driven_device_test_config = None):
    """The tradefed_test_suite macro groups all three test types under a single test_suite.o

    This enables users or tools to simply run 'b test //path/to:foo_test_suite' and bazel
    can automatically determine which of the device or deviceless variants to run, using
    target_compatible_with information from the test_dep target.


    Args:
      name: name of the test suite. This is the canonical name of the test, e.g. "hello_world_test".
      test_dep: label of the language-specific test dependency.
      test_config: label of a custom Tradefed XML config. if specified, skip auto generation with default configs.
      template_configs: additional lines to be added to the test config.
      template_install_base: the default install location on device for files.
      tags: additional tags for the top level test_suite target. This can be used for filtering tests.
      visibility: Bazel visibility declarations for this target.
      test_language: language used for the test dependency. One of [LANGUAGE_CC, LANGUAGE_JAVA].
      deviceless_test_config: default Tradefed test config for the deviceless execution mode.
      device_driven_test_config: default Tradefed test config for the device driven execution mode.
      host_driven_device_test_config: default Tradefed test config for the host driven execution mode.
    """

    # Validate names.
    if not test_dep.endswith(TEST_DEP_SUFFIX) or test_dep.removesuffix(TEST_DEP_SUFFIX) != name:
        fail("tradefed_test_suite.test_dep must be named %s%s, " % (name, TEST_DEP_SUFFIX) +
             "but got %s" % test_dep)

    # Shared attributes between all three test types. The only difference between them
    # are the default template_test_config at this level.
    common_tradefed_attrs = dict(
        [
            ("test", test_dep),
            # User-specified test config should take precedence over auto-generated ones.
            ("test_config", test_config),
            # Extra lines to go into the test config.
            ("template_configs", template_configs),
            # Path to install the test executable on device.
            ("template_install_base", template_install_base),
            # Test language helps to determine test_executable and fit test into config templates.
            ("test_language", test_language),
            # There shouldn't be package-external dependencies on the internal tests.
            ("visibility", ["//visibility:private"]),
            # The internal tests shouldn't run with ... or :all target patterns
            ("tags", ["manual"]),
            # Tradefed harness always builds for host.
            ("target_compatible_with", ["//build/bazel/platforms/os:linux"]),
        ],
    )

    # Tradefed deviceless test. Device NOT necessary. Tradefed will be invoked with --null-device.
    tradefed_deviceless_test_name = name + "__tf_deviceless_test"
    tests = [tradefed_deviceless_test_name]
    tradefed_deviceless_test(
        name = tradefed_deviceless_test_name,
        template_test_config = None if test_config else deviceless_test_config,
        **common_tradefed_attrs
    )

    # | type             | deviceless / unit     | device-driven | host-driven device |
    # |------------------+-----------------------+---------------+--------------------|
    # | java_test_host   | YES                   |               | YES                |
    # | java_test        | YES if host_supported | YES           |                    |
    # | cc_test_host     | YES                   |               | YES                |
    # | cc_test          | YES if host_supported | YES           |                    |
    # | python_test_host | YES                   |               | YES                |
    # | python_test      | YES if host_supported | YES           |                    |
    # | android_test     |                       | YES           |                    |
    if device_driven_test_config and host_driven_device_test_config:
        fail("%s: device tests cannot be both device driven and host driven at the same time." % name)

    # Tradefed host or device driven device test. Device necessary.
    if device_driven_test_config or host_driven_device_test_config:
        tradefed_device_test_name = name + "__tf_device_test"
        tests.append(tradefed_device_test_name)
        if device_driven_test_config:
            tradefed_device_driven_test(
                name = tradefed_device_test_name,
                template_test_config = None if test_config else device_driven_test_config,
                **common_tradefed_attrs
            )
        else:
            tradefed_host_driven_device_test(
                name = tradefed_device_test_name,
                template_test_config = None if test_config else host_driven_device_test_config,
                **common_tradefed_attrs
            )

    native.test_suite(
        name = name,
        tests = tests,
        visibility = visibility,
        # Warning: be careful when specifying tags here, as tags have special
        # meaning in test suites for filtering tests.
        tags = tags,
        target_compatible_with = ["//build/bazel/platforms/os:linux"],
    )

def _abspath(relative):
    return "${TEST_SRCDIR}/${TEST_WORKSPACE}/" + relative

def _classpath(jars):
    return ":".join([_abspath(f.short_path) for f in depset(jars).to_list()])
