load("//build/bazel/bazel_sandwich:run_test_in_build.bzl", "run_test_in_build")
load("//build/bazel/rules/partitions:partition.bzl", "partition")
load("//build/bazel/rules/partitions/diff:partition_diff.bzl", "partition_diff_test")

package(default_visibility = ["//visibility:public"])

partition(
    name = "system_image",
    base_staging_dir = "//build/bazel/bazel_sandwich:system_staging_dir",
    base_staging_dir_file_list = "//build/bazel/bazel_sandwich:system_staging_dir_file_list",
    image_properties = """
system_fs_type=ext4
system_reserved_size=67108864
building_system_image=true
ext_mkuserimg=mkuserimg_mke2fs
fs_type=ext4
squashfs_sparse_flag=-s
f2fs_sparse_flag=-S
erofs_default_compressor=lz4hc,9
ext4_share_dup_blocks=true
use_dynamic_partition_size=true
skip_fsck=true
""",
    root_dir = "//build/bazel/bazel_sandwich:root_staging_dir",
    type = "system",
    deps = [
        #"//build/bazel/examples/apex/minimal:build.bazel.examples.apex.minimal",
    ],
)

partition_diff_test(
    name = "test",
    partition1 = "//build/bazel/bazel_sandwich:make_system_image",
    partition2 = ":system_image",
)

run_test_in_build(
    name = "run_test",
    test = ":test",
)
