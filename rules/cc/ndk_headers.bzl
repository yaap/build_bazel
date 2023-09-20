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
`ndk_headers` provides a CcInfo for building SDK variants of CC libraries.
Unlike cc_library_headers, it has a `from` and `to` attribute that can be used to create an import path for headers that
is different than the checked-in folder layout.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")

def _ndk_headers_impl(ctx):
    # Copy the hdrs to a synthetic root
    outs = []
    for hdr in ctx.files.hdrs:
        rel_to_package = paths.relativize(
            hdr.path,
            ctx.label.package,
        )
        rel_after_strip_import = paths.relativize(
            rel_to_package,
            ctx.attr.strip_import_prefix,
        )
        out = ctx.actions.declare_file(
            paths.join(
                ctx.label.name,
                ctx.attr.import_prefix,
                rel_after_strip_import,
            ),
        )

        ctx.actions.run_shell(
            inputs = depset(direct = [hdr]),
            outputs = [out],
            command = "cp -f %s %s" % (hdr.path, out.path),
            mnemonic = "CopyFile",
            use_default_shell_env = True,
        )
        outs.append(out)

    compilation_context = cc_common.create_compilation_context(
        headers = depset(outs),
        # ndk_headers are provided as -isystem and not -I
        # https://cs.android.com/android/_/android/platform/build/soong/+/main:cc/compiler.go;l=394-403;drc=e0202c4823d1b3cabf63206d3a6611868d1559e1;bpv=1;bpt=0
        system_includes = depset([
            paths.join(ctx.bin_dir.path, ctx.label.package, ctx.label.name),
        ]),
    )
    return [
        DefaultInfo(files = depset(outs)),
        CcInfo(compilation_context = compilation_context),
    ]

ndk_headers = rule(
    implementation = _ndk_headers_impl,
    attrs = {
        "strip_import_prefix": attr.string(
            doc =
                """
            The prefix to strip from the .h files of this target.
            e.g if the hdrs are `dir/foo.h` and strip_import_prefix is `dir`, then rdeps will include it as #include <foo.h>
            """,
            default = "",
        ),
        "import_prefix": attr.string(
            doc =
                """
            The prefix to add to the .h files of this target.
            e.g if the hdrs are `dir/foo.h` and import_prefix is `dir_prefix`, then rdeps will include it as #include <dir_prefix/dir/foo.h>
            """,
            default = "",
        ),
        "hdrs": attr.label_list(
            doc = ".h files contributed by the library to the Public API surface (NDK)",
            allow_files = True,
        ),
    },
    provides = [CcInfo],
)
