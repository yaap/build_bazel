#!/usr/bin/env python3
#
# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Utility functions to produce module or module type dependency graphs using json-module-graph or queryview."""

import collections
import json
import os
import os.path
import subprocess
import sys
import xml.etree.ElementTree

# This list of module types are omitted from the report and graph
# for brevity and simplicity. Presence in this list doesn't mean
# that they shouldn't be converted, but that they are not that useful
# to be recorded in the graph or report currently.
IGNORED_KINDS = set([
    "license_kind",
    "license",
    "cc_defaults",
    "cc_prebuilt_object",
    "cc_prebuilt_library_headers",
    "cc_prebuilt_library_shared",
    "cc_prebuilt_library_static",
    "cc_prebuilt_library_static",
    "cc_prebuilt_library",
    "java_defaults",
    "ndk_prebuilt_static_stl",
    "ndk_library",
])

SRC_ROOT_DIR = os.path.abspath(__file__ + "/../../../../..")


def _build_with_soong(target):
  subprocess.check_output(
      [
          "build/soong/soong_ui.bash",
          "--make-mode",
          "--skip-soong-tests",
          target,
      ],
      cwd=SRC_ROOT_DIR,
      env={
          # Use aosp_arm as the canonical target product.
          "TARGET_PRODUCT": "aosp_arm",
          "TARGET_BUILD_VARIANT": "userdebug",
      },
  )


def get_queryview_module_info(module):
  """Returns the list of transitive dependencies of input module as built by queryview."""
  _build_with_soong("queryview")

  queryview_xml = subprocess.check_output(
      [
          "tools/bazel", "query", "--config=ci", "--config=queryview",
          "--output=xml",
          'deps(attr("soong_module_name", "^{}$", //...))'.format(module)
      ],
      cwd=SRC_ROOT_DIR,
  )
  try:
    return xml.etree.ElementTree.fromstring(queryview_xml)
  except xml.etree.ElementTree.ParseError as err:
    error_msg = """Could not parse XML:
{xml}
ParseError: {err}""".format(
    xml=queryview_xml, err=err)
    print(error_msg, file=sys.stderr)
    exit(1)


def get_json_module_info(module):
  """Returns the list of transitive dependencies of input module as provided by Soong's json module graph."""
  _build_with_soong("json-module-graph")
  # Run query.sh on the module graph for the top level module
  jq_json = subprocess.check_output(
      [
          "build/bazel/json_module_graph/query.sh", "fullTransitiveDeps",
          "out/soong/module-graph.json", module
      ],
      cwd=SRC_ROOT_DIR,
  )
  try:
    return json.loads(jq_json)
  except json.JSONDecodeError as err:
    error_msg = """Could not decode json:
{json}
JSONDecodeError: {err}""".format(
    json=jq_json, err=err)
    print(error_msg, file=sys.stderr)
    exit(1)


def module_graph_from_json(module_graph, ignore_by_name, filter_predicate,
                           visit):
  # The set of ignored modules. These modules (and their dependencies) are not shown
  # in the graph or report.
  ignored = set()

  # name to all module variants
  module_graph_map = collections.defaultdict(list)
  root_module_names = []

  # Do a single pass to find all top-level modules to be ignored
  for module in module_graph:
    name = module["Name"]
    if is_windows_variation(module):
      continue
    if ignore_kind(module["Type"]) or name in ignore_by_name:
      ignored.add(name)
      continue
    module_graph_map[name].append(module)
    if filter_predicate(module):
      root_module_names.append(name)

  visited = set()

  def json_module_graph_post_traversal(module_name):
    if module_name in ignored or module_name in visited:
      return
    visited.add(module_name)

    deps = set()
    for module in module_graph_map[module_name]:
      for dep in module["Deps"]:
        if ignore_json_dep(dep, module_name, ignored):
          continue

        dep_name = dep["Name"]
        deps.add(dep_name)

        if dep_name not in visited:
          json_module_graph_post_traversal(dep_name)

      visit(module, deps)

  for module_name in root_module_names:
    json_module_graph_post_traversal(module_name)


def get_bp2build_converted_modules():
  """ Returns the list of modules that bp2build can currently convert. """
  _build_with_soong("bp2build")
  # Parse the list of converted module names from bp2build
  with open(
      os.path.join(
          SRC_ROOT_DIR,
          "out/soong/soong_injection/metrics/converted_modules.txt")) as f:
    # Read line by line, excluding comments.
    # Each line is a module name.
    ret = [line.strip() for line in f.readlines() if not line.startswith("#")]
  return set(ret)


def get_json_module_type_info(module_type):
  """Returns the combined transitive dependency closures of all modules of module_type."""
  _build_with_soong("json-module-graph")
  # Run query.sh on the module graph for the top level module type
  result = subprocess.check_output(
      [
          "build/bazel/json_module_graph/query.sh",
          "fullTransitiveModuleTypeDeps", "out/soong/module-graph.json",
          module_type
      ],
      cwd=SRC_ROOT_DIR,
  )
  return json.loads(result)


def is_windows_variation(module):
  """Returns True if input module's variant is Windows.

  Args:
    module: an entry parsed from Soong's json-module-graph
  """
  dep_variations = module.get("Variations")
  dep_variation_os = ""
  if dep_variations != None:
    for v in dep_variations:
      if v["Mutator"] == "os":
        dep_variation_os = v["Variation"]
  return dep_variation_os == "windows"


def ignore_kind(kind):
  return kind in IGNORED_KINDS or "defaults" in kind


def ignore_json_dep(dep, module_name, ignored_names):
  """Whether to ignore a json dependency based on heuristics.

  Args:
    dep: dependency struct from an entry in Soogn's json-module-graph
    module_name: name of the module this is a dependency of
    ignored_names: a set of names to ignore
  """
  name = dep["Name"]
  return name in ignored_names or name == module_name
