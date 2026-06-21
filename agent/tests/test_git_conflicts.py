"""
Git merge conflict parser and resolution tests.

Covers: parse_conflicts(), apply_resolution(), ConflictBlock, ConflictRegion.
Mirrors the behavior of VS Code's mergeConflictParser.ts.
"""

from __future__ import annotations

import pytest

from mobileflow_agent.services.git_service import (
    ConflictBlock,
    ConflictRegion,
    apply_resolution,
    parse_conflicts,
)


# ── Test fixtures ──

SIMPLE_CONFLICT = """\
line 1
line 2
<<<<<<< HEAD
our code
=======
their code
>>>>>>> feature/xyz
line 8
line 9
"""

TWO_CONFLICTS = """\
top
<<<<<<< HEAD
ours1
=======
theirs1
>>>>>>> branch-a
middle
<<<<<<< HEAD
ours2 line1
ours2 line2
=======
theirs2
>>>>>>> branch-b
bottom
"""

DIFF3_CONFLICT = """\
before
<<<<<<< HEAD
our version
||||||| merged common ancestors
original version
=======
their version
>>>>>>> feature
after
"""

EMPTY_CURRENT = """\
<<<<<<< HEAD
=======
their stuff
>>>>>>> branch
"""

EMPTY_INCOMING = """\
<<<<<<< HEAD
our stuff
=======
>>>>>>> branch
"""

MALFORMED_NESTED = """\
<<<<<<< HEAD
our code
<<<<<<< NESTED
nested start
=======
their code
>>>>>>> branch
"""

NO_SPLITTER = """\
<<<<<<< HEAD
missing splitter
>>>>>>> branch
"""

NEWLINE_ONLY_CONTENT = """\
<<<<<<< HEAD

=======
replacement
>>>>>>> branch
"""


class TestParseConflicts:
    """Test parse_conflicts() — state machine parser."""

    def test_simple_conflict(self):
        """Single conflict with one line each side."""
        blocks = parse_conflicts(SIMPLE_CONFLICT)
        assert len(blocks) == 1

        b = blocks[0]
        assert b.id == 0
        assert b.current.label == "HEAD"
        assert b.current.content == "our code\n"
        assert b.incoming.label == "feature/xyz"
        assert b.incoming.content == "their code\n"
        assert b.range_start == 2
        assert b.range_end == 6

    def test_two_conflicts(self):
        """Multiple conflicts in one file."""
        blocks = parse_conflicts(TWO_CONFLICTS)
        assert len(blocks) == 2

        assert blocks[0].id == 0
        assert blocks[0].current.content == "ours1\n"
        assert blocks[0].incoming.content == "theirs1\n"
        assert blocks[0].incoming.label == "branch-a"

        assert blocks[1].id == 1
        assert blocks[1].current.content == "ours2 line1\nours2 line2\n"
        assert blocks[1].incoming.content == "theirs2\n"
        assert blocks[1].incoming.label == "branch-b"

    def test_diff3_mode_skips_ancestor(self):
        """diff3 mode (|||||||) — ancestor content is skipped."""
        blocks = parse_conflicts(DIFF3_CONFLICT)
        assert len(blocks) == 1

        b = blocks[0]
        assert b.current.content == "our version\n"
        assert b.incoming.content == "their version\n"
        # Ancestor block should not appear in either region
        assert "original version" not in b.current.content
        assert "original version" not in b.incoming.content

    def test_empty_current_block(self):
        """Current block is empty (nothing between <<<<<<< and =======)."""
        blocks = parse_conflicts(EMPTY_CURRENT)
        assert len(blocks) == 1
        # Empty content results in empty string (no trailing newline)
        assert blocks[0].current.content == ""
        assert blocks[0].incoming.content == "their stuff\n"

    def test_empty_incoming_block(self):
        """Incoming block is empty (nothing between ======= and >>>>>>>)."""
        blocks = parse_conflicts(EMPTY_INCOMING)
        assert len(blocks) == 1
        assert blocks[0].current.content == "our stuff\n"
        assert blocks[0].incoming.content == ""

    def test_malformed_nested_start_breaks(self):
        """Nested <<<<<<< inside a conflict — VS Code breaks parsing."""
        blocks = parse_conflicts(MALFORMED_NESTED)
        # VS Code behavior: break on nested start marker, return nothing
        assert len(blocks) == 0

    def test_no_splitter_skips(self):
        """Missing ======= — conflict is incomplete, skipped."""
        blocks = parse_conflicts(NO_SPLITTER)
        assert len(blocks) == 0

    def test_no_conflicts(self):
        """Normal file with no conflict markers."""
        blocks = parse_conflicts("just\nsome\nnormal\ncode\n")
        assert len(blocks) == 0

    def test_empty_file(self):
        """Empty file."""
        blocks = parse_conflicts("")
        assert len(blocks) == 0

    def test_newline_only_current(self):
        """Current content is just a newline."""
        blocks = parse_conflicts(NEWLINE_ONLY_CONTENT)
        assert len(blocks) == 1
        # Single empty line between <<<<<<< and =======
        assert blocks[0].current.content == "\n"

    def test_to_dict(self):
        """ConflictBlock.to_dict() serializes correctly."""
        blocks = parse_conflicts(SIMPLE_CONFLICT)
        d = blocks[0].to_dict()
        assert d["id"] == 0
        assert d["current_label"] == "HEAD"
        assert d["incoming_label"] == "feature/xyz"
        assert "current_content" in d
        assert "incoming_content" in d
        assert "range_start" in d
        assert "range_end" in d


class TestApplyResolution:
    """Test apply_resolution() — single conflict replacement."""

    def test_accept_current(self):
        """Accept current keeps our code, removes markers."""
        blocks = parse_conflicts(SIMPLE_CONFLICT)
        result = apply_resolution(SIMPLE_CONFLICT, blocks[0], "current")
        assert "our code" in result
        assert "their code" not in result
        assert "<<<<<<<" not in result
        assert "=======" not in result
        assert ">>>>>>>" not in result
        # Surrounding lines preserved
        assert "line 1" in result
        assert "line 9" in result

    def test_accept_incoming(self):
        """Accept incoming keeps their code, removes markers."""
        blocks = parse_conflicts(SIMPLE_CONFLICT)
        result = apply_resolution(SIMPLE_CONFLICT, blocks[0], "incoming")
        assert "their code" in result
        assert "our code" not in result
        assert "<<<<<<<" not in result

    def test_accept_both(self):
        """Accept both concatenates current + incoming."""
        blocks = parse_conflicts(SIMPLE_CONFLICT)
        result = apply_resolution(SIMPLE_CONFLICT, blocks[0], "both")
        assert "our code" in result
        assert "their code" in result
        # Current comes before incoming
        assert result.index("our code") < result.index("their code")
        assert "<<<<<<<" not in result

    def test_newline_only_becomes_empty(self):
        """VS Code behavior: newline-only content resolves to empty."""
        blocks = parse_conflicts(NEWLINE_ONLY_CONTENT)
        result = apply_resolution(NEWLINE_ONLY_CONTENT, blocks[0], "current")
        # Newline-only content should be replaced with empty
        assert "<<<<<<<" not in result
        assert ">>>>>>>" not in result

    def test_invalid_resolution_raises(self):
        """Invalid resolution value raises ValueError."""
        blocks = parse_conflicts(SIMPLE_CONFLICT)
        with pytest.raises(ValueError, match="Invalid resolution"):
            apply_resolution(SIMPLE_CONFLICT, blocks[0], "invalid")

    def test_resolve_first_of_two(self):
        """Resolving first conflict preserves second conflict intact."""
        blocks = parse_conflicts(TWO_CONFLICTS)
        result = apply_resolution(TWO_CONFLICTS, blocks[0], "current")
        # First conflict resolved
        assert "ours1" in result
        assert "theirs1" not in result
        # Second conflict still has markers
        remaining = parse_conflicts(result)
        assert len(remaining) == 1
        assert remaining[0].current.content == "ours2 line1\nours2 line2\n"

    def test_resolve_second_of_two(self):
        """Resolving second conflict preserves first conflict intact."""
        blocks = parse_conflicts(TWO_CONFLICTS)
        result = apply_resolution(TWO_CONFLICTS, blocks[1], "incoming")
        assert "theirs2" in result
        # First conflict still has markers
        remaining = parse_conflicts(result)
        assert len(remaining) == 1
        assert remaining[0].incoming.content == "theirs1\n"

    def test_resolve_all_bottom_up(self):
        """Resolving all conflicts bottom-to-top preserves correctness."""
        blocks = parse_conflicts(TWO_CONFLICTS)
        content = TWO_CONFLICTS
        # Process from bottom to top (like VS Code acceptAll)
        for block in reversed(blocks):
            content = apply_resolution(content, block, "current")
        remaining = parse_conflicts(content)
        assert len(remaining) == 0
        assert "ours1" in content
        assert "ours2 line1" in content
        assert "<<<<<<<" not in content

    def test_empty_block_resolution(self):
        """Resolving empty current block gives empty replacement."""
        blocks = parse_conflicts(EMPTY_CURRENT)
        result = apply_resolution(EMPTY_CURRENT, blocks[0], "current")
        # Empty current → file should not contain the incoming content
        assert "their stuff" not in result
        assert "<<<<<<<" not in result


class TestConflictRegion:
    """Test ConflictRegion data model."""

    def test_to_dict(self):
        r = ConflictRegion(label="HEAD", content="code\n", start_line=3, end_line=4)
        d = r.to_dict()
        assert d["label"] == "HEAD"
        assert d["content"] == "code\n"
        assert d["start_line"] == 3
        assert d["end_line"] == 4
