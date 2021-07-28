load(":apex_key.bzl", "ApexKeyInfo")
load(":apex_settings.bzl", "ApexEnabledInfo")

# See the APEX section in the README on how to use this rule.
def _apex_rule_impl(ctx):
    if not ctx.attr._enable_apex[ApexEnabledInfo].enabled:
        print("Skipping " + ctx.label.name + ". Pass --//build/bazel/rules:enable_apex=True to build APEXes.")
        return

    # Create testdata layout for the APEX filesystem image as a tree artifact.
    apex_testdata_dir = ctx.actions.declare_directory("apex_testdata")
    ctx.actions.run_shell(
        outputs = [apex_testdata_dir],
        mnemonic = "ApexTestDataDir",
        command = "mkdir -p %s && touch %s/file-in-apex" % (apex_testdata_dir.path, apex_testdata_dir.path),
    )

    # conv_apex_manifest - Convert the JSON APEX manifest to protobuf, which is needed by apexer.
    apex_manifest_json = ctx.file.manifest
    apex_manifest_pb = ctx.actions.declare_file("apex_manifest.pb")

    ctx.actions.run(
        outputs = [apex_manifest_pb],
        inputs = [ctx.file.manifest],
        executable = ctx.executable._conv_apex_manifest,
        arguments = [
            "proto",
            apex_manifest_json.path,
            "-o", apex_manifest_pb.path
        ],
        mnemonic = "ConvApexManifest"
    )

    # generate fs config. This encodes the filemode, uid, and gid of each file in the APEX,
    # including apex_manifest.json and apex_manifest.pb.
    canned_fs_config = ctx.actions.declare_file("canned_fs_config")
    ctx.actions.write(
        canned_fs_config,
        """/ 1000 1000 0755
/apex_manifest.json 1000 1000 0644
/apex_manifest.pb 1000 1000 0644
/file-in-apex 1000 1000 0644""")


    # apexer - generate the APEX file.
    file_contexts = ctx.file.file_contexts

    apex_key_info = ctx.attr.key[ApexKeyInfo]
    privkey = apex_key_info.private_key
    pubkey = apex_key_info.public_key

    android_jar = ctx.file._android_jar

    apex_output = ctx.actions.declare_file(ctx.attr.name + ".apex")

    args = ctx.actions.args()
    args.add("--verbose")
    args.add("--force")
    args.add("--include_build_info")
    args.add_all(["--manifest", apex_manifest_pb.path])
    args.add_all(["--manifest_json", apex_manifest_json.path])
    args.add_all(["--file_contexts", file_contexts.path])
    args.add_all(["--canned_fs_config", canned_fs_config.path])
    args.add_all(["--key", privkey.path])
    args.add_all(["--pubkey", pubkey.path])
    args.add_all(["--payload_type", "image"])
    args.add_all(["--target_sdk_version", "10000"])
    args.add_all(["--min_sdk_version", ctx.attr.min_sdk_version])
    args.add_all(["--payload_fs_type", "ext4"])
    # Input dir
    args.add(apex_testdata_dir.path)
    # Output APEX
    args.add(apex_output.path)

    ctx.actions.run(
        inputs = [
            apex_testdata_dir,
            apex_manifest_json,
            apex_manifest_pb,
            file_contexts,
            canned_fs_config,
            privkey,
            pubkey,
            android_jar,
        ],
        use_default_shell_env = True, # needed for APEXER_TOOL_PATH
        outputs = [apex_output],
        executable = ctx.executable._apexer,
        arguments = [args],
        mnemonic = "Apexer",
    )

    files_to_build = depset([apex_output])

    return [DefaultInfo(files = files_to_build)]

_apex = rule(
    implementation = _apex_rule_impl,
    attrs = {
        "manifest": attr.label(allow_single_file = [".json"]),
        "android_manifest": attr.label(allow_single_file = [".xml"]),
        "file_contexts": attr.label(allow_single_file = True),
        "key": attr.label(providers = [ApexKeyInfo]),
        "certificate": attr.label(allow_single_file = True),
        "min_sdk_version": attr.string(),
        "updatable": attr.bool(default = True),
        "installable": attr.bool(default = True),
        "native_shared_libs": attr.label_list(),
        "binaries": attr.label_list(),
        "_apexer": attr.label(
            allow_single_file = True,
            cfg = "host",
            executable = True,
            default = "//build/bazel/rules/prebuilts:apexer"
        ),
        "_conv_apex_manifest": attr.label(
            allow_single_file = True,
            cfg = "host",
            executable = True,
            default = "//build/bazel/rules/prebuilts:conv_apex_manifest"
        ),
        "_android_jar": attr.label(
            allow_single_file = True,
            cfg = "host",
            default = "//prebuilts/sdk/current:public/android.jar",
        ),
        "_enable_apex": attr.label(default = "//build/bazel/rules:enable_apex")
    },
)

def apex(
    name,
    manifest = "apex_manifest.json",
    android_manifest = None,
    file_contexts = None,
    key = None,
    certificate = None,
    min_sdk_version = None,
    updatable = True,
    installable = True,
    native_shared_libs = [],
    binaries = [],
    **kwargs):
    "Bazel macro to correspond with the APEX bundle Soong module."

    _apex(
        name = name,
        manifest = manifest,
        android_manifest = android_manifest,
        file_contexts = file_contexts,
        key = key,
        certificate = certificate,
        min_sdk_version = min_sdk_version,
        updatable = updatable,
        installable = installable,
        native_shared_libs = native_shared_libs,
        binaries = binaries,
        **kwargs,
    )