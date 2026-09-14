# Copyright 2026 The Kubernetes Authors.
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

"""Unit tests for :mod:`devops_bench.evalharness.artifacts`."""

from __future__ import annotations

from pathlib import Path

from devops_bench.evalharness.artifacts import persist_agent_streams


def test_persist_agent_streams_writes_both_files_when_both_are_present(tmp_path: Path) -> None:
    written = persist_agent_streams(
        raw_stdout='{"type": "init"}\n',
        raw_stderr="warning: something\n",
        run_dir=tmp_path,
    )
    stream_path = tmp_path / "agent-stream.jsonl"
    stderr_path = tmp_path / "agent-stderr.log"
    assert stream_path.read_text(encoding="utf-8") == '{"type": "init"}\n'
    assert stderr_path.read_text(encoding="utf-8") == "warning: something\n"
    assert set(written) == {"agent-stream.jsonl", "agent-stderr.log"}


def test_persist_agent_streams_skips_empty_stdout_and_stderr(tmp_path: Path) -> None:
    written = persist_agent_streams(raw_stdout="", raw_stderr="", run_dir=tmp_path)
    assert written == []
    assert not (tmp_path / "agent-stream.jsonl").exists()
    assert not (tmp_path / "agent-stderr.log").exists()


def test_persist_agent_streams_writes_only_the_non_empty_stream(tmp_path: Path) -> None:
    written = persist_agent_streams(raw_stdout="only stdout\n", raw_stderr="", run_dir=tmp_path)
    assert (tmp_path / "agent-stream.jsonl").exists()
    assert not (tmp_path / "agent-stderr.log").exists()
    assert written == ["agent-stream.jsonl"]


def test_persist_agent_streams_writes_content_verbatim_without_reformatting(
    tmp_path: Path,
) -> None:
    raw = '{"type": "tool_use", "timestamp": "2026-09-14T16:43:14.684Z"}\nnot-quite-json\n'
    persist_agent_streams(raw_stdout=raw, raw_stderr="", run_dir=tmp_path)
    assert (tmp_path / "agent-stream.jsonl").read_text(encoding="utf-8") == raw
