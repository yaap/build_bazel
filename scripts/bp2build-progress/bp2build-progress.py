#!/usr/bin/env python3
#
# Copyright (C) 2021 The Android Open Source Project
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
"""A json-module-graph postprocessing script to generate a bp2build progress tracker.

Usage:
  ./bp2build-progress.py [report|graph] -m <module name>

Example:

  To generate a report on the `adbd` module, run:
    ./bp2build-progress report -m adbd

  To generate a graph on the `adbd` module, run:
    ./bp2build-progress graph -m adbd > graph.in && dot -Tpng -o graph.png
    graph.in

"""

import argparse
import collections
import datetime
import dependency_analysis
import os.path
import subprocess
import sys
import xml
from typing import Dict, List, Set

_ModuleInfo = collections.namedtuple("_ModuleInfo", [
    "name",
    "kind",
    "dirname",
])

_ReportData = collections.namedtuple("_ReportData", [
    "input_module",
    "all_unconverted_modules",
    "blocked_modules",
    "dirs_with_unconverted_modules",
    "kind_of_unconverted_modules",
    "converted",
])


def combine_report_data(data):
  ret = _ReportData(
      input_module=set(),
      all_unconverted_modules=collections.defaultdict(set),
      blocked_modules=collections.defaultdict(set),
      dirs_with_unconverted_modules=set(),
      kind_of_unconverted_modules=set(),
      converted=set(),
  )
  for item in data:
    ret.input_module.add(item.input_module)
    for key, value in item.all_unconverted_modules.items():
      ret.all_unconverted_modules[key].update(value)
    for key, value in item.blocked_modules.items():
      ret.blocked_modules[key].update(value)
    ret.dirs_with_unconverted_modules.update(item.dirs_with_unconverted_modules)
    ret.kind_of_unconverted_modules.update(item.kind_of_unconverted_modules)
    if len(ret.converted) == 0:
      ret.converted.update(item.converted)
  return ret


# Generate a dot file containing the transitive closure of the module.
def generate_dot_file(
    modules: Dict[_ModuleInfo, Set[str]],
    converted: Set[str]):
  # Check that all modules in the argument are in the list of converted modules
  all_converted = lambda modules: all(m in converted for m in modules)

  dot_entries = []

  for module, deps in modules.items():
    if module.name in converted:
      # Skip converted modules (nodes)
      continue

    dot_entries.append(
        f'"{module.name}" [label="{module.name}\\n{module.kind}" color=black, style=filled, '
        f"fillcolor={'yellow' if all_converted(deps) else 'tomato'}]")
    dot_entries.extend(f'"{module.name}" -> "{dep}"' for dep in deps if dep not in converted)

  print("""
digraph mygraph {{
  node [shape=box];

  %s
}}
""" % "\n  ".join(dot_entries))


# Generate a report for each module in the transitive closure, and the blockers for each module
def generate_report_data(modules, converted, input_module):
  # Map of [number of unconverted deps] to list of entries,
  # with each entry being the string: "<module>: <comma separated list of unconverted modules>"
  blocked_modules = collections.defaultdict(set)

  # Map of unconverted modules to the modules they're blocking
  # (i.e. reverse deps)
  all_unconverted_modules = collections.defaultdict(set)

  dirs_with_unconverted_modules = set()
  kind_of_unconverted_modules = set()

  for module, deps in sorted(modules.items()):
    unconverted_deps = set(dep for dep in deps if dep not in converted)
    for dep in unconverted_deps:
      all_unconverted_modules[dep].add(module)

    unconverted_count = len(unconverted_deps)
    if module.name not in converted:
      report_entry = "{name} [{kind}] [{dirname}]: {unconverted_deps}".format(
          name=module.name,
          kind=module.kind,
          dirname=module.dirname,
          unconverted_deps=", ".join(sorted(unconverted_deps)))
      blocked_modules[unconverted_count].add(report_entry)
      dirs_with_unconverted_modules.add(module.dirname)
      kind_of_unconverted_modules.add(module.kind)

  return _ReportData(
      input_module=input_module,
      all_unconverted_modules=all_unconverted_modules,
      blocked_modules=blocked_modules,
      dirs_with_unconverted_modules=dirs_with_unconverted_modules,
      kind_of_unconverted_modules=kind_of_unconverted_modules,
      converted=converted,
  )


def generate_report(report_data):
  report_lines = []
  input_modules = sorted(report_data.input_module)

  report_lines.append("# bp2build progress report for: %s\n" % input_modules)
  report_lines.append("Ignored module types: %s\n" %
                      sorted(dependency_analysis.IGNORED_KINDS))
  report_lines.append("# Transitive dependency closure:")

  for count, modules in sorted(report_data.blocked_modules.items()):
    report_lines.append("\n%d unconverted deps remaining:" % count)
    for module_string in sorted(modules):
      report_lines.append("  " + module_string)

  report_lines.append("\n")
  report_lines.append("# Unconverted deps of {}:\n".format(input_modules))
  for count, dep in sorted(
      ((len(unconverted), dep)
       for dep, unconverted in report_data.all_unconverted_modules.items()),
      reverse=True):
    report_lines.append("%s: blocking %d modules" % (dep, count))

  report_lines.append("\n")
  report_lines.append("# Dirs with unconverted modules:\n\n{}".format("\n".join(
      sorted(report_data.dirs_with_unconverted_modules))))

  report_lines.append("\n")
  report_lines.append("# Kinds with unconverted modules:\n\n{}".format(
      "\n".join(sorted(report_data.kind_of_unconverted_modules))))

  report_lines.append("\n")
  report_lines.append("# Converted modules:\n\n%s" %
                      "\n".join(sorted(report_data.converted)))

  report_lines.append("\n")
  report_lines.append(
      "Generated by: https://cs.android.com/android/platform/superproject/+/master:build/bazel/scripts/bp2build-progress/bp2build-progress.py"
  )
  report_lines.append("Generated at: %s" %
                      datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S %z"))
  print("\n".join(report_lines))


def adjacency_list_from_json(
    module_graph: ...,
    ignore_by_name: List[str],
    top_level_module: str) -> Dict[_ModuleInfo, Set[str]]:
  def filter_by_name(json):
    return json["Name"] == top_level_module

  module_adjacency_list = collections.defaultdict(set)
  name_to_info = {}

  def collect_transitive_dependencies(module, deps_names):
    module_info = None
    name = module["Name"]
    name_to_info.setdefault(
        name,
        _ModuleInfo(
            name=name,
            kind=module["Type"],
            dirname=os.path.dirname(module["Blueprint"]),
        ))
    module_info = name_to_info[name]

    module_adjacency_list[module_info].update(deps_names)
    # account for transitive deps
    for dep in deps_names:
      dep_module_info = name_to_info[dep]
      module_adjacency_list[module_info].update(
          module_adjacency_list.get(dep_module_info, set()))

  dependency_analysis.visit_json_module_graph_post_order(
      module_graph, ignore_by_name, filter_by_name,
      collect_transitive_dependencies)

  return module_adjacency_list


def adjacency_list_from_queryview_xml(
    module_graph: xml.etree.ElementTree,
    ignore_by_name: List[str],
    top_level_module: str) -> Dict[_ModuleInfo, Set[str]]:

  def filter_by_name(module):
    return module.name == top_level_module

  module_adjacency_list = collections.defaultdict(set)
  name_to_info = {}

  def collect_transitive_dependencies(module, deps_names):
    module_info = None
    name_to_info.setdefault(
        module.name,
        _ModuleInfo(
            name=module.name,
            kind=module.kind,
            dirname=module.dirname,
        ))
    module_info = name_to_info[module.name]

    module_adjacency_list[module_info].update(deps_names)
    for dep in deps_names:
      dep_module_info = name_to_info[dep]
      module_adjacency_list[module_info].update(
          module_adjacency_list.get(dep_module_info, set()))

  dependency_analysis.visit_queryview_xml_module_graph_post_order(
      module_graph, ignore_by_name, filter_by_name,
      collect_transitive_dependencies)

  return module_adjacency_list


def get_module_adjacency_list(
    top_level_module: str,
    use_queryview: bool,
    ignore_by_name: List[str],
    banchan_mode: bool) -> Dict[_ModuleInfo, Set[str]]:
  # The main module graph containing _all_ modules in the Soong build,
  # and the list of converted modules.
  try:
    if use_queryview:
      module_graph = dependency_analysis.get_queryview_module_info(
          top_level_module, banchan_mode)
      module_adjacency_list = adjacency_list_from_queryview_xml(
          module_graph, ignore_by_name, top_level_module)
    else:
      module_graph = dependency_analysis.get_json_module_info(
          top_level_module, banchan_mode)
      module_adjacency_list = adjacency_list_from_json(
          module_graph, ignore_by_name, top_level_module)
  except subprocess.CalledProcessError as err:
    sys.exit(f"""Error running: '{' '.join(err.cmd)}':"
Stdout:
{err.stdout.decode('utf-8') if err.stdout else ''}
Stderr:
{err.stderr.decode('utf-8') if err.stderr else ''}""")

  return module_adjacency_list


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("mode", help="mode: graph or report")
  parser.add_argument(
      "--module",
      "-m",
      action="append",
      required=True,
      help="name(s) of Soong module(s). Multiple modules only supported for report"
  )
  parser.add_argument(
      "--use-queryview",
      action="store_true",
      help="whether to use queryview or module_info")
  parser.add_argument(
      "--ignore-by-name",
      default="",
      help="Comma-separated list. When building the tree of transitive dependencies, will not follow dependency edges pointing to module names listed by this flag."
  )
  parser.add_argument(
      "--banchan",
      action="store_true",
      help="whether to run Soong in a banchan configuration rather than lunch",
  )
  args = parser.parse_args()

  if len(args.module) > 1 and args.mode != "report":
    sys.exit(f"Can only support one module with mode {args.mode}")

  mode = args.mode
  use_queryview = args.use_queryview
  ignore_by_name = args.ignore_by_name.split(",")
  banchan_mode = args.banchan

  report_infos = []
  for top_level_module in args.module:
    module_adjacency_list = get_module_adjacency_list(
        top_level_module, use_queryview, ignore_by_name, banchan_mode)
    converted = dependency_analysis.get_bp2build_converted_modules()

    if mode == "graph":
      generate_dot_file(module_adjacency_list, converted)
    elif mode == "report":
      report_infos.append(
          generate_report_data(module_adjacency_list, converted,
                               top_level_module))
    else:
      raise RuntimeError("unknown mode: %s" % mode)

  if mode == "report":
    combined_data = combine_report_data(report_infos)
    generate_report(combined_data)


if __name__ == "__main__":
  main()
