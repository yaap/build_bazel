#!/usr/bin/env python3
#
# Copyright (C) 2022 The Android Open Source Project
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
"""A tool to print human-readable metrics information regarding the last build.

By default, the consumed files will be located in $ANDROID_BUILD_TOP/out/. You
may pass in a different directory instead using the metrics_files_dir flag.
"""

import argparse
import json
import os
import subprocess
import sys

from google.protobuf import json_format
from metrics_proto.metrics_pb2 import SoongBuildMetrics, MetricsBase
from bazel_metrics_proto.bazel_metrics_pb2 import BazelMetrics
from bp2build_metrics_proto.bp2build_metrics_pb2 import Bp2BuildMetrics

class Event(object):
  """Contains nested event data.

  Fields:
    name: The short name of this event e.g. the 'b' in an event called a.b.
    start_time_relative_ns: Time since the epoch that the event started
    duration_ns: Duration of this event, including time spent in children.
  """

  def __init__(self, name, start_time_relative_ns, duration_ns):
    self.name = name
    self.start_time_relative_ns = start_time_relative_ns
    self.duration_ns = duration_ns


def _get_output_file(output_dir, filename):
  file_base = os.path.splitext(filename)[0]
  return os.path.join(output_dir, file_base + ".json")


def _get_default_out_dir(metrics_dir):
  return os.path.join(metrics_dir, "analyze_build_output")


def _get_default_metrics_dir():
  """Returns the filepath for the build output."""
  out_dir = os.getenv("OUT_DIR")
  if out_dir:
    return out_dir
  build_top = os.getenv("ANDROID_BUILD_TOP")
  if not build_top:
    raise Exception(
        "$ANDROID_BUILD_TOP not found in environment. Have you run lunch?"
    )
  return os.path.join(build_top, "out")


def _write_event(out, event):
  """Writes an event. See _write_events for args."""
  out.write(
      "%(start)9s  %(duration)9s  %(name)s\n"
      % {
          "start": _format_ns(event.start_time_relative_ns),
          "duration": _format_ns(event.duration_ns),
          "name": event.name,
      }
  )


def _print_metrics_event_times(description, metrics):
  # Bail if there are no events
  raw_events = metrics.events
  if not raw_events:
    print("%s: No events to display" % description)
    return
  print("-- %s events --" % description)

  # Update the start times to be based on the first event
  first_time_ns = min([event.start_time for event in raw_events])
  events = [
      Event(getattr(e, 'description', e.name), e.start_time - first_time_ns, e.real_time)
      for e in raw_events
  ]

  # Sort by start time so the nesting also is sorted by time
  events.sort(key=lambda x: x.start_time_relative_ns)

  # Output the results
  print("    start   duration")

  for event in events:
    _write_event(sys.stdout, event)
  print()

def _format_ns(duration_ns):
  "Pretty print duration in nanoseconds"
  return "%.02fs" % (duration_ns / 1_000_000_000)


def _read_data(filepath, proto):
  with open(filepath, "rb") as f:
    proto.ParseFromString(f.read())
    f.close()


def _maybe_save_data(proto, filename, args):
  if args.skip_metrics:
    return
  json_out = json_format.MessageToJson(proto)
  output_filepath = _get_output_file(args.output_dir, filename)
  _save_file(json_out, output_filepath)


def _save_file(data, file):
  with open(file, "w") as f:
    f.write(data)
    f.close()


def _handle_missing_metrics(args, filename):
  """Handles cleanup for a metrics file that doesn't exist.

  This will delete any output files under the tool's output directory that
  would have been generated as a result of a metrics file from a previous
  build. This prevents stale analysis files from polluting the output dir."""
  if args.skip_metrics:
    # If skip_metrics is enabled, then don't write or delete any data.
    return
  output_filepath = _get_output_file(args.output_dir, filename)
  if os.path.exists(output_filepath):
    os.remove(output_filepath)


def main():
  # Parse args
  parser = argparse.ArgumentParser(
      description=(
          "Parses metrics protocol buffer files from the user's most recent"
          " build and prints "
          + " metrics events in a user-friendly format. Information will be"
          " saved by default in "
          + " out/analyze_build_output."
      )
      + " It will also save those protos in a json format by default.",
      prog="analyze_build",
  )
  parser.add_argument(
      "metrics_files_dir",
      nargs="?",
      default=_get_default_metrics_dir(),
      help="The directory contained metrics files to analyze."
      + " Defaults to $OUT_DIR if set, $ANDROID_BUILD_TOP/out otherwise.",
  )
  parser.add_argument(
      "--skip-metrics",
      action="store_true",
      help="If set, do not save the output of printproto commands.",
  )
  parser.add_argument(
      "output_dir",
      nargs="?",
      help="The directory to save analyzed proto output to. "
      + "If unspecified, will default to the directory specified with"
      " --metrics_files_dir + '/analyze_build_output/'",
  )
  args = parser.parse_args()

  # Check the metrics file
  metrics_files_dir = args.metrics_files_dir
  args.output_dir = args.output_dir or _get_default_out_dir(metrics_files_dir)
  if not args.skip_metrics:
    os.makedirs(args.output_dir, exist_ok=True)
    print("Writing build analysis files to "+args.output_dir, file=sys.stderr)

  if not os.path.exists(metrics_files_dir):
    raise Exception(
        "File " + metrics_files_dir + " not found. Did you run a build?"
    )

  bp2build_file = os.path.join(metrics_files_dir, "bp2build_metrics.pb")
  if os.path.exists(bp2build_file):
    bp2build_metrics = Bp2BuildMetrics()
    _read_data(bp2build_file, bp2build_metrics)
    _print_metrics_event_times("bp2build", bp2build_metrics)
    _maybe_save_data(bp2build_metrics, "bp2build_metrics.pb", args)
  else:
    _handle_missing_metrics(args, "bp2build_metrics.pb")

  soong_build_file = os.path.join(metrics_files_dir, "soong_build_metrics.pb")
  if os.path.exists(soong_build_file):
    soong_build_metrics = SoongBuildMetrics()
    _read_data(soong_build_file, soong_build_metrics)
    _print_metrics_event_times("soong_build", soong_build_metrics)
    _maybe_save_data(soong_build_metrics, "soong_build_metrics.pb", args)
  else:
    _handle_missing_metrics(args, "soong_build_metrics.pb")

  soong_metrics_file = os.path.join(metrics_files_dir, "soong_metrics")
  if os.path.exists(soong_metrics_file):
    metrics_base = MetricsBase()
    _read_data(soong_metrics_file, metrics_base)
    _maybe_save_data(metrics_base, "soong_metrics", args)
  else:
    _handle_missing_metrics(args, "soong_metrics")

  bazel_metrics_file = os.path.join(metrics_files_dir, "bazel_metrics.pb")
  if os.path.exists(bazel_metrics_file):
    bazel_metrics = BazelMetrics()
    _read_data(bazel_metrics_file, bazel_metrics)
    _maybe_save_data(bazel_metrics, "bazel_metrics.pb", args)
  else:
    _handle_missing_metrics(args, "bazel_metrics.pb")


if __name__ == "__main__":
  main()
