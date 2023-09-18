load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//build/bazel/rules/common:api_internal.bzl", "api_internal")

def _is_preview_test_impl(ctx):
    env = unittest.begin(ctx)

    # schema: version string to parse: is preview api
    _LEVELS_UNDER_TEST = {
        # numbers
        "9": False,  # earliest released number
        # codenames
        "Tiramisu": False,
        "UpsideDownCake": True,  # preview
        "current": True,  # future (considered as preview)
        "(no version)": True,
        # preview numbers
        "9000": True,  # preview
        "10000": True,  # future (considered as preview)
    }

    for level, expected in _LEVELS_UNDER_TEST.items():
        asserts.equals(env, expected, api_internal.is_preview(level, {"UpsideDownCake": 9000}), "unexpected is_preview value for %s" % level)

    return unittest.end(env)

is_preview_test = unittest.make(_is_preview_test_impl)

def _default_app_target_sdk_string_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        "33",
        api_internal.default_app_target_sdk_string(True, 33, "REL"),
        "unexpected default_app_target_sdk_string value with platform_sdk_final True and platform_sdk_version 33.",
    )
    asserts.equals(
        env,
        "VanillaIceCream",
        api_internal.default_app_target_sdk_string(False, 33, "VanillaIceCream"),
        "unexpected default_app_target_sdk_string value with platform_sdk_final False and platform_sdk_codename VanillaIceCream.",
    )

    return unittest.end(env)

default_app_target_sdk_string_test = unittest.make(_default_app_target_sdk_string_test_impl)

def _effective_version_string_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        "32",
        api_internal.effective_version_string("32", {"UpsideDownCake": 9000}, "33", ["UpsideDownCake"]),
        "unexpected effective version string when input version (32) is not preview",
    )
    asserts.equals(
        env,
        "33",
        api_internal.effective_version_string("current", {"UpsideDownCake": 9000}, "33", ["UpsideDownCake"]),
        "unexpected effective version string when input version (current) is not preview and default_app_target_sdk (33) is not.",
    )
    asserts.equals(
        env,
        "VanillaIceCream",
        api_internal.effective_version_string("VanillaIceCream", {"UpsideDownCake": 9000, "VanillaIceCream": 9001}, "UpsideDownCake", ["UpsideDownCake", "VanillaIceCream"]),
        "unexpected effective version string when both input version (VanillaIceCream) and default_app_target_sdk (UpsideDownCake) are preview.",
    )
    asserts.equals(
        env,
        "UpsideDownCake",
        api_internal.effective_version_string("current", {"UpsideDownCake": 9000, "VanillaIceCream": 9001}, "UpsideDownCake", ["UpsideDownCake", "VanillaIceCream"]),
        "unexpected effective version string when both input version (current) and default_app_target_sdk (UpsideDownCake) are preview.",
    )

    return unittest.end(env)

effective_version_string_test = unittest.make(_effective_version_string_test_impl)

def api_internal_test_suite(name):
    unittest.suite(
        name,
        is_preview_test,
        default_app_target_sdk_string_test,
        effective_version_string_test,
    )
