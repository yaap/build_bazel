load("//build/bazel/rules:cc_library_headers.bzl", "cc_library_headers")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cpp_toolchain")

# "cc_object" module copts, taken from build/soong/cc/object.go
_CC_OBJECT_COPTS = ["-fno-addrsig"]

def _cc_object_impl(ctx):
    cc_toolchain = find_cpp_toolchain(ctx)

    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    (compilation_context, compilation_outputs) = cc_common.compile(
        name = ctx.label.name,
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        srcs = ctx.files.srcs,
        public_hdrs = ctx.files.hdrs,
        private_hdrs = ctx.files.private_hdrs,
        quote_includes = ctx.attr.includes,
        user_compile_flags = ctx.attr.copts,
        compilation_contexts = [dep[CcInfo].compilation_context for dep in ctx.attr.deps],
    )

    object_files = compilation_outputs.pic_objects + compilation_outputs.objects
    transitive_files = [dep[DefaultInfo].files for dep in ctx.attr.deps]
    output_files = depset(object_files, transitive = transitive_files)

    return [
        DefaultInfo(files = output_files),
        CcInfo(compilation_context = compilation_context)
    ]

_cc_object = rule(
    implementation = _cc_object_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".c", ".cc", ".cpp", ".S"]),
        "hdrs": attr.label_list(allow_files = [".h"]),
        "private_hdrs": attr.label_list(allow_files = [".h"]),
        "includes": attr.string_list(),
        "copts": attr.string_list(),
        "deps": attr.label_list(),
        "_cc_toolchain": attr.label(
            default = Label("@local_config_cc//:toolchain"),
            providers = [cc_common.CcToolchainInfo],
        ),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)

def cc_object(
        name,
        copts = [],
        local_include_dirs = [],
        srcs = [],
        deps = [],
        native_bridge_supported = False, # TODO: not supported yet.
        **kwargs):
    "Build macro to correspond with the cc_object Soong module."

    # convert local_include_dirs to cc_library_headers deps
    include_deps = []
    for dir in local_include_dirs:
        dep_name = "generated__" + dir + "_includes" # may contain slashes, but valid label anyway.
        include_deps += [dep_name]

        # Since multiple cc_objects can refer to the same cc_library_headers dep, avoid
        # generating duplicate deps by using native.existing_rule.
        if native.existing_rule(dep_name) == None:
            cc_library_headers(
                name = dep_name,
                includes = [dir],
                strip_include_prefix = dir,
                include_prefix = dir,
                hdrs = native.glob([dir + "/**/*.h"]),
            )

    # combine deps and include deps
    all_deps = deps + include_deps

    # Simulate hdrs_check = 'loose' by allowing src files to reference headers
    # directly in the directories they are in.
    globs = {}
    for src in srcs:
        dir_name = src.split("/")[:-1]
        dir_name += ["*.h"]
        dir_glob = "/".join(dir_name)
        globs[dir_glob] = True
    hdrs = native.glob(globs.keys())

    _cc_object(
        name = name,
        private_hdrs = hdrs,
        copts = _CC_OBJECT_COPTS + copts,
        srcs = srcs,
        deps = all_deps,
        **kwargs
    )
