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

# An API level, can be a finalized (numbered) API, a preview (codenamed) API, or
# the future API level (10000). Can be parsed from a string with
# parse_api_level_with_version.

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@soong_injection//api_levels:platform_versions.bzl", "platform_versions")
load(":api_constants.bzl", "api_levels_released_versions")
load(":api_internal.bzl", "api_internal")

# TODO(b/300428335): access these variables in a transition friendly way.
_PLATFORM_SDK_FINAL = platform_versions.platform_sdk_final
_PLATFORM_SDK_VERSION = platform_versions.platform_sdk_version
_PLATFORM_SDK_CODENAME = platform_versions.platform_sdk_codename
_PLATFORM_VERSION_ACTIVE_CODENAMES = platform_versions.platform_version_active_codenames

# Dict of unfinalized codenames to a placeholder preview API int.
_preview_codenames_to_ints = api_internal.preview_codenames_to_ints(_PLATFORM_VERSION_ACTIVE_CODENAMES)

# Returns true if a string or int version is in preview (not finalized).
def _is_preview(version, platform_sdk_variables):
    return api_internal.is_preview(
        version = version,
        preview_codenames_to_ints = api_internal.preview_codenames_to_ints(
            platform_sdk_variables.platform_version_active_codenames,
        ),
    )

# Return 10000 for unfinalized versions, otherwise return unchanged.
def _final_or_future(version):
    if api_internal.is_preview(version, _preview_codenames_to_ints):
        return api_internal.FUTURE_API_LEVEL
    else:
        return version

_final_codename = {
    "current": _final_or_future(_PLATFORM_SDK_VERSION),
} if _PLATFORM_SDK_FINAL and _PLATFORM_SDK_VERSION else {}

_api_levels_with_previews = dicts.add(api_levels_released_versions, _preview_codenames_to_ints)
_api_levels_with_final_codenames = dicts.add(api_levels_released_versions, _final_codename)  # @unused

# parse_api_level_from_version is a Starlark implementation of ApiLevelFromUser
# at https://cs.android.com/android/platform/superproject/+/master:build/soong/android/api_levels.go;l=221-250;drc=5095a6c4b484f34d5c4f55a855d6174e00fb7f5e
def _parse_api_level_from_version(version):
    """converts the given string `version` to an api level

    Args:
        version: must be non-empty. Inputs that are not "current", known
        previews, finalized codenames, or convertible to an integer will return
        an error.

    Returns: The api level as an int.
    """
    if version == "":
        fail("API level string must be non-empty")

    if version == "current":
        return api_internal.FUTURE_API_LEVEL

    if api_internal.is_preview(version = version, preview_codenames_to_ints = _preview_codenames_to_ints):
        return _preview_codenames_to_ints.get(version) or int(version)

    # Not preview nor current.
    #
    # If the level is the codename of an API level that has been finalized, this
    # function returns the API level number associated with that API level. If
    # the input is *not* a finalized codename, the input is returned unmodified.
    canonical_level = api_levels_released_versions.get(version)
    if not canonical_level:
        if not version.isdigit():
            fail("version %s could not be parsed as integer and is not a recognized codename" % version)
        return int(version)
    return canonical_level

# Starlark implementation of DefaultAppTargetSDK from build/soong/android/config.go
# https://cs.android.com/android/platform/superproject/+/master:build/soong/android/config.go;l=875-889;drc=b0dc477ef740ec959548fe5517bd92ac4ea0325c
# check what you want returned for codename == "" case before using
def _default_app_target_sdk(platform_sdk_variables):
    """default_app_target_sdk returns the API level that platform apps are targeting.
       This converts a codename to the exact ApiLevel it represents.
    """
    return _parse_api_level_from_version(
        api_internal.default_app_target_sdk_string(
            platform_sdk_final = platform_sdk_variables.platform_sdk_final,
            platform_sdk_version = platform_sdk_variables.platform_sdk_version,
            platform_sdk_codename = platform_sdk_variables.platform_sdk_codename,
        ),
    )

# Starlark implementation of EffectiveVersionString from build/soong/android/api_levels.go
# EffectiveVersionString converts an api level string into the concrete version string that the module
# should use. For modules targeting an unreleased SDK (meaning it does not yet have a number)
# it returns the codename (P, Q, R, etc.)
def _effective_version_string(version, platform_sdk_variables):
    return api_internal.effective_version_string(
        version,
        api_internal.preview_codenames_to_ints(
            platform_sdk_variables.platform_version_active_codenames,
        ),
        api_internal.default_app_target_sdk_string(
            platform_sdk_final = platform_sdk_variables.platform_sdk_final,
            platform_sdk_version = platform_sdk_variables.platform_sdk_version,
            platform_sdk_codename = platform_sdk_variables.platform_sdk_codename,
        ),
        platform_sdk_variables.platform_version_active_codenames,
    )

api_from_product = lambda platform_sdk_variables: struct(
    NONE_API_LEVEL = api_internal.NONE_API_LEVEL,
    FUTURE_API_LEVEL = api_internal.FUTURE_API_LEVEL,
    is_preview = lambda version: _is_preview(
        version = version,
        platform_sdk_variables = platform_sdk_variables,
    ),
    final_or_future = _final_or_future,
    default_app_target_sdk = lambda: _default_app_target_sdk(platform_sdk_variables),
    parse_api_level_from_version = _parse_api_level_from_version,
    api_levels = _api_levels_with_previews,
    effective_version_string = lambda version: _effective_version_string(
        version = version,
        platform_sdk_variables = platform_sdk_variables,
    ),
)

api = api_from_product(struct(
    platform_sdk_final = _PLATFORM_SDK_FINAL,
    platform_sdk_version = _PLATFORM_SDK_VERSION,
    platform_sdk_codename = _PLATFORM_SDK_CODENAME,
    platform_version_active_codenames = _PLATFORM_VERSION_ACTIVE_CODENAMES,
))
