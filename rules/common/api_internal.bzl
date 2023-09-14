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

visibility("private")

_NONE_API_LEVEL_INT = -1
_PREVIEW_API_LEVEL_BASE = 9000  # Base constant for preview API levels.
_FUTURE_API_LEVEL_INT = 10000  # API Level associated with an arbitrary future release

# Dict of unfinalized codenames to a placeholder preview API int.
def _preview_codenames_to_ints(platform_version_active_codenames):
    return {
        codename: _PREVIEW_API_LEVEL_BASE + i
        for i, codename in enumerate(platform_version_active_codenames)
    }

def _is_preview(version, preview_codenames_to_ints):
    if type(version) == "string" and version.isdigit():
        # normalize int types internally
        version = int(version)

    # Future / current / none is considered as a preview.
    if version in ("current", "(no version)", _FUTURE_API_LEVEL_INT, _NONE_API_LEVEL_INT):
        return True

    # api can be either the codename or the int level (9000+)
    return version in preview_codenames_to_ints or version in preview_codenames_to_ints.values()

def _default_app_target_sdk_string(platform_sdk_final, platform_sdk_version, platform_sdk_codename):
    if platform_sdk_final:
        return str(platform_sdk_version)

    if not platform_sdk_codename:
        # soong returns NoneApiLevel here value: "(no version)", number: -1, isPreview: true
        #
        # fail fast instead of returning an arbitrary value.
        fail("Platform_sdk_codename must be set.")

    if platform_sdk_codename == "REL":
        fail("Platform_sdk_codename should not be REL when Platform_sdk_final is false")

    return platform_sdk_codename

def _effective_version_string(
        version,
        preview_codenames_to_ints,
        default_app_target_sdk_string,
        platform_version_active_codenames):
    if not _is_preview(version, preview_codenames_to_ints):
        return version
    if not _is_preview(default_app_target_sdk_string, preview_codenames_to_ints):
        return default_app_target_sdk_string
    if version in platform_version_active_codenames:
        return version
    return default_app_target_sdk_string

api_internal = struct(
    NONE_API_LEVEL = _NONE_API_LEVEL_INT,
    FUTURE_API_LEVEL = _FUTURE_API_LEVEL_INT,
    preview_codenames_to_ints = _preview_codenames_to_ints,
    is_preview = _is_preview,
    default_app_target_sdk_string = _default_app_target_sdk_string,
    effective_version_string = _effective_version_string,
)
