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

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load(
    "@bazel_tools//tools/build_defs/cc:action_names.bzl",
    "CPP_COMPILE_ACTION_NAME",
    "C_COMPILE_ACTION_NAME",
)

def _get_compilation_args(toolchain, feature_config, flags, compilation_ctx, action_name):
    compilation_vars = cc_common.create_compile_variables(
        cc_toolchain = toolchain,
        feature_configuration = feature_config,
        user_compile_flags = flags,
        include_directories = compilation_ctx.includes,
        quote_include_directories = compilation_ctx.quote_includes,
        system_include_directories = compilation_ctx.system_includes,
        framework_include_directories = compilation_ctx.framework_includes,
    )

    return cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_config,
        action_name = action_name,
        variables = compilation_vars,
    )

def _add_header_filter(ctx, tidy_flags):
    """If TidyFlags does not contain -header-filter, add default header filter.
    """
    for flag in tidy_flags:
        # Find the substring because the flag could also appear as --header-filter=...
        # and with or without single or double quotes.
        if "-header-filter=" in flag:
            return tidy_flags

    # Default header filter should include only the module directory,
    # not the out/soong/.../ModuleDir/...
    # Otherwise, there will be too many warnings from generated files in out/...
    # If a module wants to see warnings in the generated source files,
    # it should specify its own -header-filter flag.
    #TODO(b/255744059) support DEFAULT_TIDY_HEADER_DIRS
    header_filter = "-header-filter=^" + ctx.label.package + "/"
    return tidy_flags + [header_filter]

def _add_extra_arg_flags(tidy_flags):
    """keep up to date with
    https://cs.android.com/android/platform/superproject/+/master:build/soong/cc/tidy.go;l=138-152;drc=ff2efae9b014d644fcce8143258fa652fc2bcf13
    TODO(b/255750565) export this
    """
    extra_arg_flags = [
        # We might be using the static analyzer through clang tidy.
        # https://bugs.llvm.org/show_bug.cgi?id=32914
        "-D__clang_analyzer__",

        # A recent change in clang-tidy (r328258) enabled destructor inlining, which
        # appears to cause a number of false positives. Until that's resolved, this turns
        # off the effects of r328258.
        # https://bugs.llvm.org/show_bug.cgi?id=37459
        "-Xclang",
        "-analyzer-config",
        "-Xclang",
        "c++-temp-dtor-inlining=false",
    ]

    return tidy_flags + ["-extra-arg-before=" + f for f in extra_arg_flags]

def _create_clang_tidy_action(ctx, clang_tool, input_file, tidy_checks, tidy_checks_as_errors, tidy_flags, clang_flags, headers):
    tidy_flags = _add_header_filter(ctx, tidy_flags)
    tidy_flags = _add_extra_arg_flags(tidy_flags)

    args = ctx.actions.args()
    args.add(input_file)
    if tidy_checks:
        args.add("-checks=" + ",".join(tidy_checks))
    if tidy_checks_as_errors:
        args.add("-warnings-as-errors=" + ",".join(tidy_checks_as_errors))
    if tidy_flags:
        args.add_all(tidy_flags)
    args.add("--")
    args.add_all(clang_flags)

    tidy_file = ctx.actions.declare_file(paths.join(ctx.label.name, input_file.short_path + ".tidy"))
    ctx.actions.run(
        inputs = [input_file] + headers,
        outputs = [tidy_file],
        arguments = [args],
        env = {
            "CLANG_CMD": clang_tool,
            "TIDY_FILE": tidy_file.path,
        },
        progress_message = "Running clang-tidy on {}".format(input_file.short_path),
        tools = [
            ctx.executable._clang_tidy,
            ctx.executable._clang_tidy_real,
        ],
        executable = ctx.executable._clang_tidy_sh,
        execution_requirements = {
            "no-sandbox": "1",
        },
    )

    return tidy_file

def generate_clang_tidy_actions(
        ctx,
        flags,
        deps,
        srcs,
        hdrs,
        language,
        tidy_flags,
        tidy_checks,
        tidy_checks_as_errors):
    """Generates actions for clang tidy

    Args:
        ctx (Context): rule context that is expected to contain
            - ctx.executable._clang_tidy
            - ctx.executable._clang_tidy_sh
            - ctx.executable._clang_tidy_real
        flags (list[str]): list of target-specific (non-toolchain) flags passed to clang compile action
        deps (list[Target]): list of Targets which provide headers to compilation context
        srcs (list[File]): list of srcs to which clang-tidy will be applied
        hdrs (list[File]): list of headers used by srcs. This is used to provide explicit inputs to the action
        language (str): must be one of ["c++", "c"]. This is used to decide what toolchain arguments are passed to the clang compile action
        tidy_flags (list[str]): additional flags to pass to the clang-tidy tool
        tidy_checks (list[str]): list of checks for clang-tidy to perform
        tidy_checks_as_errors (list[str]): list of checks to pass as "-warnings-as-errors" to clang-tidy
    Returns:
        tidy_file_outputs: (list[File]): list of .tidy files output by the clang-tidy.sh tool
    """
    toolchain = find_cpp_toolchain(ctx)
    feature_config = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = toolchain,
        language = "c++",
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    language = language
    action_name = ""
    if language == "c++":
        action_name = CPP_COMPILE_ACTION_NAME
    elif language == "c":
        action_name = C_COMPILE_ACTION_NAME
    else:
        fail("invalid language:", language)

    dep_info = cc_common.merge_cc_infos(direct_cc_infos = [d[CcInfo] for d in deps])
    compilation_ctx = dep_info.compilation_context
    args = _get_compilation_args(
        toolchain = toolchain,
        feature_config = feature_config,
        flags = flags,
        compilation_ctx = compilation_ctx,
        action_name = action_name,
    )

    clang_tool = cc_common.get_tool_for_action(
        feature_configuration = feature_config,
        action_name = action_name,
    )

    header_inputs = (
        hdrs +
        compilation_ctx.headers.to_list() +
        compilation_ctx.direct_headers +
        compilation_ctx.direct_private_headers +
        compilation_ctx.direct_public_headers +
        compilation_ctx.direct_textual_headers
    )

    tidy_file_outputs = []
    for src in srcs:
        tidy_file = _create_clang_tidy_action(
            ctx = ctx,
            input_file = src,
            headers = header_inputs,
            clang_tool = paths.basename(clang_tool),
            tidy_checks = tidy_checks,
            tidy_checks_as_errors = tidy_checks_as_errors,
            tidy_flags = tidy_flags,
            clang_flags = args,
        )
        tidy_file_outputs.append(tidy_file)

    return tidy_file_outputs
