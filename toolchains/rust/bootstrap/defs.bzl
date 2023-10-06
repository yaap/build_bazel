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

"""
This file contains rule and transition for building rust toolchain for device
"""

# Flags common to builds of the standard library.
_EXTRA_FLAGS_FOR_STDLIB_BUILDS = [
    "-Ccodegen-units=2",
    # Use v0 symbol mangling, see b/261148332.
    "-Csymbol-mangling-version=v0",
    # Always keep frame pointers, see b/258819642.
    "-Cforce-frame-pointers=yes",
]

_TRANSITION_OUTPUTS = [
    "//command_line_option:compilation_mode",
    "//command_line_option:extra_toolchains",
    "@rules_rust//:extra_rustc_flags",
    "@rules_rust//:extra_exec_rustc_flags",
    "@rules_rust//rust/settings:use_real_import_macro",
    "@rules_rust//rust/settings:pipelined_compilation",
    "//command_line_option:cpu",
]

def _base_transition_impl(_, __):
    return {
        "//command_line_option:compilation_mode": "opt",
        "//command_line_option:cpu": "k8",
        "//command_line_option:extra_toolchains": ["//build/bazel/toolchains/rust/bootstrap:android_arm64_base_rust_toolchain"],
        "@rules_rust//:extra_rustc_flags": _EXTRA_FLAGS_FOR_STDLIB_BUILDS,
        "@rules_rust//:extra_exec_rustc_flags": _EXTRA_FLAGS_FOR_STDLIB_BUILDS,
        "@rules_rust//rust/settings:use_real_import_macro": False,
        "@rules_rust//rust/settings:pipelined_compilation": True,
    }

_base_transition = transition(
    inputs = ["//command_line_option:extra_toolchains"],
    outputs = _TRANSITION_OUTPUTS,
    implementation = _base_transition_impl,
)

# Re-exports libs passed in `srcs` attribute. Used together with
# transitions to build stdlibs at various stages.
def _with_base_transition_impl(ctx):
    return [DefaultInfo(files = depset(ctx.files.srcs))]

with_base_transition = rule(
    implementation = _with_base_transition_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = Label("@bazel_tools//tools/allowlists/function_transition_allowlist"),
        ),
    },
    cfg = _base_transition,
)

def _toolchain_sysroot_impl(ctx):
    sysroot = ctx.attr.dirname
    outputs = []

    rustlibdir = "{}/lib/rustlib/{}/lib".format(sysroot, ctx.attr.target_triple)
    rustbindir = "{}/bin".format(sysroot)

    for inp in ctx.files.srcs:
        if inp.short_path in ctx.attr.tools:
            out = ctx.actions.declare_file(rustbindir + "/" + ctx.attr.tools[inp.short_path])
        else:
            out = ctx.actions.declare_file(rustlibdir + "/" + inp.basename)

        outputs.append(out)
        ctx.actions.symlink(output = out, target_file = inp)

    return [DefaultInfo(
        files = depset(outputs),
        runfiles = ctx.runfiles(files = outputs),
    )]

toolchain_sysroot = rule(
    implementation = _toolchain_sysroot_impl,
    doc = """Creates a directory tree with copies of the passed Rust libraries
    and tools, suitable to use in a rust_stdlib_filegroup.

    The `srcs` attribute should enumerate the libraries and tools. Tools are
    distinguished from libraries via the `tools` attribute, which should
    contain an entry from the tool short_path to its final name under
    dirname/bin/

    The libraries are processed by creating symlinks to them in a local
    directory rooted at `dirname`, e.g.,
    dirname/lib/rustlib/x86_64-unknown-linux-gnu/lib/

    The output under `dirname` is intended to constitute a valid sysroot, per
    https://rustc-dev-guide.rust-lang.org/building/bootstrapping.html#what-is-a-sysroot
    """,
    attrs = {
        "dirname": attr.string(
            mandatory = True,
        ),
        "target_triple": attr.string(
            doc = "The target triple for the rlibs.",
            default = "x86_64-unknown-linux-gnu",
        ),
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "tools": attr.string_dict(
            doc = "A map from tool's short_path to its final name under bin/",
        ),
    },
)
