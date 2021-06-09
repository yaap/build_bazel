load("//prebuilts/clang/host/linux-x86:clang_version.bzl", "DEFAULT_VERSION")

# This test requires bp2build to run and the generated BUILD files in the source tree.
sh_test(
    name = "verify_bionic_outputs",
    srcs = ["verify_bionic_outputs.sh"],
    data = [
        "//bionic/libc:libc",
        "//bionic/libdl:libdl_android",
        "//bionic/linker:ld-android",
        "//prebuilts/clang/host/linux-x86:test_tools",
    ],
    env = {"CLANG_DEFAULT_VERSION": DEFAULT_VERSION},
    deps = ["@bazel_tools//tools/bash/runfiles"],
)
