load("@//build/bazel/tests/products:aosp_arm.variables.bzl", _soong_variables_arm = "variables")
load("@//build/bazel/tests/products:aosp_arm64.variables.bzl", _soong_variables_arm64 = "variables")
load("@//build/bazel/tests/products:aosp_x86.variables.bzl", _soong_variables_x86 = "variables")
load("@//build/bazel/tests/products:aosp_x86_64.variables.bzl", _soong_variables_x86_64 = "variables")
load("@bazel_skylib//lib:dicts.bzl", "dicts")

products = {
    "aosp_arm_for_testing": _soong_variables_arm,
    "aosp_arm_for_testing_custom_linker_alignment": dicts.add(
        _soong_variables_arm,
        {"DeviceMaxPageSizeSupported": "65536"},
    ),
    "aosp_arm64_for_testing": _soong_variables_arm64,
    "aosp_arm64_for_testing_custom_linker_alignment": dicts.add(
        _soong_variables_arm64,
        {"DeviceMaxPageSizeSupported": "16384"},
    ),
    "aosp_arm64_for_testing_no_compression": dicts.add(
        _soong_variables_arm64,
        {"CompressedApex": False},
    ),
    "aosp_arm64_for_testing_unbundled_build": dicts.add(
        _soong_variables_arm64,
        {"Unbundled_build": True},
    ),
    "aosp_arm64_for_testing_with_overrides_and_app_cert": dicts.add(
        _soong_variables_arm64,
        {
            "ManifestPackageNameOverrides": [
                "apex_certificate_label_with_overrides:another",
                "package_name_override_from_config:another.package",
            ],
            "CertificateOverrides": [
                "apex_certificate_label_with_overrides:another",
            ],
            "DefaultAppCertificate": "build/bazel/rules/apex/testdata/devkey",
        },
    ),
    "aosp_x86_for_testing": _soong_variables_x86,
    "aosp_x86_for_testing_cfi_include_path": dicts.add(
        _soong_variables_x86,
        {"CFIIncludePaths": ["build/bazel/rules/cc"]},
    ),
    "aosp_x86_for_testing_cfi_exclude_path": dicts.add(
        _soong_variables_x86,
        {"CFIExcludePaths": ["build/bazel/rules/cc"]},
    ),
    "aosp_x86_64_for_testing": _soong_variables_x86_64,
    "aosp_arm64_for_testing_min_sdk_version_override_tiramisu": dicts.add(
        _soong_variables_arm64,
        {"ApexGlobalMinSdkVersionOverride": "Tiramisu"},
    ),
}

product_labels = [
    "@//build/bazel/tests/products:" + name
    for name in products.keys()
]
