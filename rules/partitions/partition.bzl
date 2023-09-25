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

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":installable_info.bzl", "InstallableInfo", "installable_aspect")

_IMAGE_TYPES = [
    "system",
    "system_other",
    "userdata",
    "cache",
    "vendor",
    "product",
    "system_ext",
    "odm",
    "vendor_dlkm",
    "system_dlkm",
    "oem",
]

def _get_python3(ctx):
    python_interpreter = ctx.toolchains["@bazel_tools//tools/python:toolchain_type"].py3_runtime.interpreter
    if python_interpreter.basename == "python3":
        return python_interpreter

    renamed = ctx.actions.declare_file("python3")
    ctx.actions.symlink(
        output = renamed,
        target_file = python_interpreter,
        is_executable = True,
    )
    return renamed

def _partition_impl(ctx):
    if ctx.attr.type != "system":
        fail("currently only system images are supported")

    toolchain = ctx.toolchains[":partition_toolchain_type"].toolchain_info
    python_interpreter = _get_python3(ctx)

    du = ctx.actions.declare_file("du")
    ctx.actions.symlink(
        output = du,
        target_file = toolchain.toybox[DefaultInfo].files_to_run.executable,
        is_executable = True,
    )
    find = ctx.actions.declare_file("find")
    ctx.actions.symlink(
        output = find,
        target_file = toolchain.toybox[DefaultInfo].files_to_run.executable,
        is_executable = True,
    )

    # build_image requires that the output file be named specifically <type>.img, so
    # put all the outputs under a name-qualified folder.
    output_image = ctx.actions.declare_file(ctx.attr.name + "/" + ctx.attr.type + ".img")

    files = {}
    for dep in ctx.attr.deps:
        files.update(dep[InstallableInfo].files)

    for v in files.keys():
        if not v.startswith("/system"):
            fail("Files outside of /system are not currently supported: %s", v)

    staging_dir_builder_options = {
        # It seems build_image will prepend /system to the paths when building_system_image=true
        "file_mapping": {k.removeprefix("/system"): v.path for k, v in files.items()},
    }

    extra_inputs = []
    if ctx.attr.base_staging_dir:
        staging_dir_builder_options["base_staging_dir"] = ctx.file.base_staging_dir.path
        extra_inputs.append(ctx.file.base_staging_dir)
        bbipi = ctx.attr._build_broken_incorrect_partition_images[BuildSettingInfo].value
        if ctx.attr.base_staging_dir_file_list and not bbipi:
            staging_dir_builder_options["base_staging_dir_file_list"] = ctx.file.base_staging_dir_file_list.path
            extra_inputs.append(ctx.file.base_staging_dir_file_list)

    image_info = ctx.actions.declare_file(ctx.attr.name + "/image_info.txt")
    image_info_contents = ctx.attr.image_properties + "\n"
    image_info_contents += "ext_mkuserimg=mkuserimg_mke2fs\n"
    if ctx.attr.root_dir:
        extra_inputs.append(ctx.file.root_dir)
        image_info_contents += "root_dir=" + ctx.file.root_dir.path + "\n"
    ctx.actions.write(image_info, image_info_contents)

    staging_dir_builder_options_file = ctx.actions.declare_file(ctx.attr.name + "/staging_dir_builder_options.json")
    ctx.actions.write(staging_dir_builder_options_file, json.encode(staging_dir_builder_options))

    build_image_files = toolchain.build_image[DefaultInfo].files_to_run

    # These are tools that are run from build_image or another tool that build_image runs.
    # They are all expected to be available in the PATH.
    extra_tools = [
        toolchain.e2fsdroid[DefaultInfo].files_to_run,
        toolchain.mke2fs[DefaultInfo].files_to_run,
        toolchain.mkuserimg_mke2fs[DefaultInfo].files_to_run,
        toolchain.simg2img[DefaultInfo].files_to_run,
        toolchain.tune2fs[DefaultInfo].files_to_run,
    ]

    ctx.actions.run(
        inputs = [
            image_info,
            staging_dir_builder_options_file,
        ] + files.values() + extra_inputs,
        tools = extra_tools + [
            build_image_files,
            du,
            find,
            python_interpreter,
            toolchain.toybox[DefaultInfo].files_to_run,
        ],
        outputs = [output_image],
        executable = ctx.executable._staging_dir_builder,
        arguments = [
            staging_dir_builder_options_file.path,
            build_image_files.executable.path,
            "STAGING_DIR_PLACEHOLDER",
            image_info.path,
            output_image.path,
            "STAGING_DIR_PLACEHOLDER",
        ],
        mnemonic = "BuildPartition",
        env = {
            # The dict + .keys() is to dedup the path elements, as some tools are in the same folder
            "PATH": ":".join({t.executable.dirname: True for t in extra_tools}.keys() + [
                python_interpreter.dirname,
                du.dirname,
                find.dirname,
            ]),
        },
    )

    return DefaultInfo(files = depset([output_image]))

_partition = rule(
    implementation = _partition_impl,
    attrs = {
        "type": attr.string(
            mandatory = True,
            values = _IMAGE_TYPES,
        ),
        "image_properties": attr.string(
            doc = "The image property dictionary in key=value format. TODO: consider replacing this with explicit bazel properties for each property in this file.",
        ),
        "base_staging_dir": attr.label(
            allow_single_file = True,
            doc = "A staging dir that the deps will be added to. This is intended to be used to import a make-built staging directory when building the partition with bazel.",
        ),
        "base_staging_dir_file_list": attr.label(
            allow_single_file = True,
            doc = "A file list that will be used to filter the base_staging_dir.",
        ),
        "deps": attr.label_list(
            providers = [[InstallableInfo]],
            aspects = [installable_aspect],
        ),
        "root_dir": attr.label(
            allow_single_file = True,
            doc = "A folder to add as the root_dir property in the property file",
        ),
        "_build_broken_incorrect_partition_images": attr.label(
            default = "//build/bazel/product_config:build_broken_incorrect_partition_images",
        ),
        "_staging_dir_builder": attr.label(
            cfg = "exec",
            doc = "The tool used to build a staging directory, because if bazel were to build it it would be entirely symlinks.",
            executable = True,
            default = "//build/bazel/rules:staging_dir_builder",
        ),
    },
    toolchains = [
        ":partition_toolchain_type",
        "@bazel_tools//tools/python:toolchain_type",
    ],
)

def partition(target_compatible_with = [], **kwargs):
    target_compatible_with = select({
        "//build/bazel/platforms/os:android": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }) + target_compatible_with
    _partition(
        target_compatible_with = target_compatible_with,
        **kwargs
    )
