defmodule CoverageReporter.UncoveredLineGrouperTest do
  use ExUnit.Case, async: true

  alias CoverageReporter.UncoveredLineGrouper

  describe "group_lines/2" do
    test "groups consecutive uncovered lines" do
      source_lines = [
        {"def function", 1},
        {"  uncovered_line_1", 2},
        {"  uncovered_line_2", 3},
        {"  covered_line", 4},
        {"end", 5}
      ]

      coverage_map = %{1 => 1, 2 => 0, 3 => 0, 4 => 1, 5 => 1}

      result = UncoveredLineGrouper.group_lines(source_lines, coverage_map)

      assert result == [[2, 3]]
    end

    test "bridges small gaps with covered lines" do
      source_lines = [
        {"def function", 1},
        {"  uncovered_line_1", 2},
        {"  covered_line", 3},
        {"  uncovered_line_2", 4},
        {"end", 5}
      ]

      coverage_map = %{1 => 1, 2 => 0, 3 => 1, 4 => 0, 5 => 1}

      result = UncoveredLineGrouper.group_lines(source_lines, coverage_map)

      assert result == [[2, 3, 4]]
    end

    test "includes blank lines in groups" do
      source_lines = [
        {"function() {", 1},
        {"  uncovered_line", 2},
        {"", 3},
        {"  another_uncovered_line", 4},
        {"}", 5}
      ]

      coverage_map = %{1 => 1, 2 => 0, 4 => 0, 5 => 1}

      result = UncoveredLineGrouper.group_lines(source_lines, coverage_map)

      assert result == [[2, 3, 4]]
    end

    test "creates separate groups for distant uncovered lines" do
      source_lines = [
        {"def function", 1},
        {"  uncovered_line_1", 2},
        {"  covered_line_1", 3},
        {"  covered_line_2", 4},
        {"  uncovered_line_2", 5},
        {"end", 6}
      ]

      coverage_map = %{1 => 1, 2 => 0, 3 => 1, 4 => 1, 5 => 0, 6 => 1}

      result = UncoveredLineGrouper.group_lines(source_lines, coverage_map)

      assert result == [[2], [5]]
    end

    test "handles single uncovered lines" do
      source_lines = [
        {"def function", 1},
        {"  covered_line", 2},
        {"  uncovered_line", 3},
        {"  covered_line", 4},
        {"end", 5}
      ]

      coverage_map = %{1 => 1, 2 => 1, 3 => 0, 4 => 1, 5 => 1}

      result = UncoveredLineGrouper.group_lines(source_lines, coverage_map)

      assert result == [[3]]
    end

    test "returns empty list when no uncovered lines" do
      source_lines = [
        {"def function", 1},
        {"  covered_line", 2},
        {"end", 3}
      ]

      coverage_map = %{1 => 1, 2 => 1, 3 => 1}

      result = UncoveredLineGrouper.group_lines(source_lines, coverage_map)

      assert result == []
    end

    test "ignores lines without LCOV data (not executable)" do
      source_lines = [
        {"# Comment line", 1},
        {"def function", 2},
        {"  uncovered_line", 3},
        {"  # Another comment", 4},
        {"  covered_line", 5},
        {"end", 6}
      ]

      # Only lines 2, 3, 5 have LCOV data - lines 1, 4, 6 are not executable
      coverage_map = %{2 => 1, 3 => 0, 5 => 1}

      result = UncoveredLineGrouper.group_lines(source_lines, coverage_map)

      # Should only group line 3 as uncovered, ignoring lines without LCOV data
      assert result == [[3, 4]]
    end

    test "bridges uncovered lines through not executable lines" do
      source_lines = [
        {"def function", 1},
        {"  uncovered_line_1", 2},
        {"  # Comment separating uncovered lines", 3},
        {"  uncovered_line_2", 4},
        {"end", 5}
      ]

      # Line 3 has no LCOV data (comment), so it's not executable
      coverage_map = %{1 => 1, 2 => 0, 4 => 0, 5 => 1}

      result = UncoveredLineGrouper.group_lines(source_lines, coverage_map)

      # Should bridge through not executable line 3 to create one group
      assert result == [[2, 3, 4]]
    end
  end
end
