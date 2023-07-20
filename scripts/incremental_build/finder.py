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
import glob
import os
import subprocess
from pathlib import Path

from util import get_out_dir
from util import get_top_dir


def is_git_repo(p: Path) -> bool:
    """checks if p is in a directory that's under git version control"""
    git = subprocess.run(
        args=f"git remote".split(),
        cwd=p,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return git.returncode == 0


def any_file(pattern: str) -> Path:
    return any_file_under(get_top_dir(), pattern)


def any_file_under(root: Path, pattern: str) -> Path:
    if pattern.startswith("!"):
        raise RuntimeError(f"provide a filename instead of {pattern}")
    d, files = any_match_under(get_top_dir() if root is None else root, pattern)
    files = [d.joinpath(f) for f in files]
    try:
        file = next(f for f in files if f.is_file())
        return file
    except StopIteration:
        raise RuntimeError(f"no file matched {pattern}")


def any_dir_under(root: Path, *patterns: str) -> Path:
    d, _ = any_match_under(root, *patterns)
    return d


def any_match(*patterns: str) -> tuple[Path, list[str]]:
    return any_match_under(get_top_dir(), *patterns)


@functools.cache
def any_match_under(root: Path, *patterns: str) -> tuple[Path, list[str]]:
    """
    Finds sub-paths satisfying the patterns
    :param patterns glob pattern to match or unmatch if starting with "!"
    :param root the first directory to start searching from
    :returns the dir and sub-paths matching the pattern
    """
    bfs: list[Path] = [root]
    while len(bfs) > 0:
        first = bfs.pop(0)
        if is_git_repo(first):
            matches: list[str] = []
            for pattern in patterns:
                negate = pattern.startswith("!")
                if negate:
                    pattern = pattern.removeprefix("!")
                try:
                    found_match = next(
                        glob.iglob(pattern, root_dir=first, recursive=True)
                    )
                except StopIteration:
                    found_match = None
                if negate and found_match is not None:
                    break
                if not negate:
                    if found_match is None:
                        break
                    else:
                        matches.append(found_match)
            else:
                return Path(first), matches

        def should_visit(c: os.DirEntry) -> bool:
            return c.is_dir() and not (
                c.is_symlink()
                or "." in c.name
                or "test" in c.name
                or Path(c.path) == get_out_dir()
            )

        children = [Path(c.path) for c in os.scandir(first) if should_visit(c)]
        children.sort()
        bfs.extend(children)
    raise RuntimeError(f"No suitable directory for {patterns}")
