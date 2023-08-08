load("@bazel_skylib//rules:common_settings.bzl", "bool_flag", "string_flag", "string_list_flag")
load(":product_variables_for_attributes.bzl", "product_variables_for_attributes")

package(default_visibility = ["//visibility:public"])

# This rule type outputs a TemplateVariableInfo provider that contains a subset of the product
# variables to be available for expansion using make-like syntax on certain rule attributes.
# Soong had this feature, so it was ported to bazel.
product_variables_for_attributes(name = "product_variables_for_attributes")

_string_list_variables = [
    "build_version_tags",
    "cfi_exclude_paths",
    "cfi_include_paths",
    "device_abi",
    "manifest_package_name_overrides",
    "tidy_checks",
    "unbundled_build_apps",
]

# TODO: b/292563629 - The following variables should be string_list_settings, but there's currently
# a bazel crash: https://github.com/bazelbuild/bazel/issues/18977
#   - device_abi
#   - manifest_package_name_overrides
#   - unbundled_build_apps
#   - tidy_checks
_string_variables = [
    "apex_global_min_sdk_version_override",
    "build_id",
    "default_app_certificate",
    "device_max_page_size_supported",
    "device_name",
    "device_product",
    "override_rs_driver",
    "platform_sdk_extension_version",
    "platform_sdk_version",
    "platform_sdk_version_or_codename",
    "platform_version_name",
    "product_brand",
    "product_manufacturer",
    "target_build_variant",
]

_bool_variables = [
    "always_use_prebuilt_sdks",
    "arc",
    "binder32bit",
    "build_from_text_stub",
    "compressed_apex",
    "debuggable",
    "device_page_size_agnostic",
    "enforce_vintf_manifest",
    "eng",
    "malloc_not_svelte",
    "malloc_pattern_fill_contents",
    "malloc_zero_contents",
    "native_coverage",
    "pdk",
    "release_aidl_use_unfrozen",
    "safestack",
    "treble_linker_namespaces",
    "uml",
    "unbundled_build",
]

[
    string_list_flag(
        name = name,
        build_setting_default = [],
    )
    for name in _string_list_variables
]

[
    string_flag(
        name = name,
        build_setting_default = "",
    )
    for name in _string_variables
]

[
    bool_flag(
        name = name,
        build_setting_default = False,
    )
    for name in _bool_variables
]

bool_flag(
    name = "enable_cfi",
    build_setting_default = True,
)

label_flag(
    name = "default_app_certificate_filegroup",
    build_setting_default = "//build/bazel/utils:empty_filegroup",
)
