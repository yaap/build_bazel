# Copyright (C) 2023 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

def _fix(
        ctx,
        manifest_fixer,
        in_manifest,
        out_manifest,
        mnemonic = "FixAndroidManifest",
        test_only = None,
        min_sdk_version = None,
        target_sdk_version = None):
    args = ctx.actions.args()
    if test_only:
        args.add("--test-only")
    if min_sdk_version:
        args.add("--minSdkVersion", min_sdk_version)
    if target_sdk_version:
        args.add("--targetSdkVersion", target_sdk_version)
    if min_sdk_version or target_sdk_version:
        args.add("--raise-min-sdk-version")
    args.add(in_manifest)
    args.add(out_manifest)
    ctx.actions.run(
        inputs = [in_manifest],
        outputs = [out_manifest],
        executable = manifest_fixer,
        arguments = [args],
        mnemonic = mnemonic,
    )

manifest_fixer = struct(
    fix = _fix,
)
