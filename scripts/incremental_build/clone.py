#!/usr/bin/env python3
#
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
import functools
import re
import shutil
import uuid
from pathlib import Path
from typing import Final

import util
from cuj import CujGroup
from cuj import CujStep
from cuj import src

_ALLOWLISTS = 'build/soong/android/allowlists/allowlists.go'


def _allowlist(module: str, count: int):
  """
  Allow-lists `module` and its clones - this does not check if the module is
  already allow-listed: which can result in an off-by-1 error in
  mixed-build-enabled module count
  """
  start = re.compile(r'^\s*ProdMixedBuildsEnabledList\s*=\s*\[]string\{\s*$')
  content = []
  with open(src(_ALLOWLISTS), "r+") as file:
    for line in file.readlines():
      content.append(line)
      if start.match(line):
        content.append(f'    "{module}",\n')
        content.extend([f'    "{module}-{i + 1}",\n' for i in range(0, count)])
    file.seek(0)
    file.writelines(content)


def _clone(androidbp: Path, module: str, count: int):
  """
  In the given Android.bp file, find the `module` and make `count` copies
  which are identical except for their names that are '{module}-{i}'
  for i=1 to `count`
  """
  name_pattern = re.compile(
      f'^(?P<prefix>\\s*name:\\s*"){module}(?P<suffix>",?)$')
  # we'll assume that the Android.bp file is properly formatted,
  # specifically, for any module definition:
  # 1. its first line matches `start_pattern` and
  # 2. its last line matches a closing curly brace, i.e. '}'
  start_pattern = re.compile(
      r'^(?P<module_type>\w+)\s*\{\s*$')  # e.g. `cc_library {`
  nameline: int = -1
  with open(androidbp, 'r+') as f:
    buffer: list[str] = []
    for line in f:
      if start_pattern.match(line):
        buffer = [line]
      elif line.rstrip() == '}':
        if nameline != -1:
          buffer.append('}')
          break
        else:
          buffer.clear()
      else:
        if nameline == -1:
          found = name_pattern.match(line) is not None
          if not found:
            buffer.clear()
          else:
            nameline = len(buffer)
        if len(buffer):
          # buffer would be empty if a module definition has not started
          # or the module definition didn't name-match
          buffer.append(line)

    if nameline == -1:
      raise RuntimeError(f'Couldn\'t find {module} in {androidbp}')

    f.seek(0, 2)  # go to the end of the file
    for i in range(1, count + 1):
      for j, line in enumerate(buffer):
        if j == nameline:
          line = re.sub(name_pattern, f'\\g<prefix>{module}-{i}\\g<suffix>',
                        line)
        f.write(line)
      f.write('\n')


def get_cuj_group(androidbp: Path, module: str) -> CujGroup:
  marker = uuid.uuid4()
  androidbp_bak: Final[Path] = util.get_out_dir().joinpath(
      f'android.bp.{marker}')
  allowlist_bak: Final[Path] = util.get_out_dir().joinpath(
      f'allowlists.go.{marker}')

  def helper(count: int):
    if not androidbp_bak.exists():
      assert not allowlist_bak.exists()
      # if first cuj_step then back up files to restore later
      shutil.copy(androidbp, androidbp_bak)
      shutil.copy(src(_ALLOWLISTS), allowlist_bak)
    else:
      shutil.copy(androidbp_bak, androidbp)
      shutil.copy(allowlist_bak, src(_ALLOWLISTS))
    _clone(androidbp, module, count)
    _allowlist(module, count)

  def revert():
    shutil.move(androidbp_bak, androidbp)
    shutil.move(allowlist_bak, src(_ALLOWLISTS))

  counts: Final[list[int]] = [1, 100, 1000, 2000, 4000, 6000, 8000, 10000]
  steps = [CujStep(verb=str(count),
                   apply_change=functools.partial(helper, count))
           for count in counts]
  steps.append(CujStep(verb='0', apply_change=revert))
  return CujGroup(f'clone-{module}', steps)
