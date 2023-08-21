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
import os
import unittest

from finder import any_match
from finder import is_git_repo
from util import get_top_dir


class UtilTest(unittest.TestCase):
    def test_is_git_repo(self):
        self.assertFalse(is_git_repo(get_top_dir()))
        self.assertTrue(is_git_repo(get_top_dir().joinpath("build/soong")))

    def test_any_match(self):
        with self.subTest("root.bp"):
            path, matches = any_match("root.bp")
            self.assertEqual(matches, ["root.bp"])
            self.assertEqual(path, get_top_dir().joinpath("build/soong"))

        with self.subTest("non-package"):
            path, matches = any_match(
                "!Android.bp",
                "!BUILD",
                "scripts/incremental_build/incremental_build.py",
            )
            self.assertEqual(
                matches, ["scripts/incremental_build/incremental_build.py"]
            )
            self.assertEqual(path, get_top_dir().joinpath("build/bazel"))

        with self.subTest("BUILD and README.md"):
            path, matches = any_match("BUILD", "README.md")
            self.assertEqual(matches, ["BUILD", "README.md"])
            self.assertTrue(path.joinpath("BUILD").exists())
            self.assertTrue(path.joinpath("README.md").exists())

        with self.subTest("BUILD without README.md"):
            path, matches = any_match("BUILD", "!README.md")
            self.assertEqual(matches, ["BUILD"])
            self.assertTrue(path.joinpath("BUILD").exists())
            self.assertFalse(path.joinpath("README.md").exists())

        with self.subTest("dir without *.bazel"):
            path, matches = any_match("!*.bazel", "*")
            self.assertGreater(len(matches), 0)
            children = os.listdir(path)
            self.assertGreater(len(children), 0)
            for child in children:
                self.assertFalse(child.endswith(".bazel"))

        with self.subTest("no BUILD or README.md"):
            path, matches = any_match("*/BUILD", "*/README.md")
            self.assertGreater(len(matches), 0)
            for m in matches:
                self.assertTrue(path.joinpath(m).exists())

        with self.subTest('no BUILD or cpp file in tree"'):
            path, matches = any_match("!**/BUILD", "**/*.cpp")
            self.assertEqual(len(matches), 1)
            self.assertTrue(path.joinpath(matches[0]).exists())
            self.assertTrue(matches[0].endswith(".cpp"))
            for _, dirs, files in os.walk(path):
                self.assertFalse("BUILD" in dirs)
                self.assertFalse("BUILD" in files)


if __name__ == "__main__":
    unittest.main()
