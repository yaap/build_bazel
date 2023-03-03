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
import os
import unittest

from util import _next_path_helper
from util import any_match
from util import get_top_dir


class UtilTest(unittest.TestCase):
  def test_next_path_helper(self):
    examples = [
        ('output', 'output-1'),
        ('output.x', 'output-1.x'),
        ('output.x.y', 'output-1.x.y'),
        ('output-1', 'output-2'),
        ('output-9', 'output-10'),
        ('output-10', 'output-11'),
    ]
    for (pattern, expected) in examples:
      with self.subTest(msg=pattern, pattern=pattern, expected=expected):
        self.assertEqual(_next_path_helper(pattern), expected)

  def test_any_match(self):
    path, matches = any_match('root.bp')
    self.assertEqual(matches, ['root.bp'])
    self.assertEqual(path, get_top_dir().joinpath('build/soong'))

    path, matches = any_match('!Android.bp', '!BUILD',
                              'scripts/incremental_build/incremental_build.py')
    self.assertEqual(matches,
                     ['scripts/incremental_build/incremental_build.py'])
    self.assertEqual(path, get_top_dir().joinpath('build/bazel'))

    path, matches = any_match('BUILD', 'README.md')
    self.assertEqual(matches, ['BUILD', 'README.md'])
    self.assertTrue(path.joinpath('BUILD').exists())
    self.assertTrue(path.joinpath('README.md').exists())

    path, matches = any_match('BUILD', '!README.md')
    self.assertEqual(matches, ['BUILD'])
    self.assertTrue(path.joinpath('BUILD').exists())
    self.assertFalse(path.joinpath('README.md').exists())

    path, matches = any_match('!*.bazel', '*')
    self.assertGreater(len(matches), 0)
    children = os.listdir(path)
    self.assertGreater(len(children), 0)
    for child in children:
      self.assertFalse(child.endswith('.bazel'))

    path, matches = any_match('*/BUILD', '*/README.md')
    self.assertGreater(len(matches), 0)
    for m in matches:
      self.assertTrue(path.joinpath(m).exists())

    path, matches = any_match('!**/BUILD', '**/*.cpp')
    self.assertEqual(len(matches), 1)
    self.assertTrue(path.joinpath(matches[0]).exists())
    self.assertTrue(matches[0].endswith('.cpp'))
    for _, dirs, files in os.walk(path):
      self.assertFalse('BUILD' in dirs)
      self.assertFalse('BUILD' in files)
