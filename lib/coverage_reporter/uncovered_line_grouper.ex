defmodule CoverageReporter.UncoveredLineGrouper do
  @moduledoc false

  # Groups consecutive uncovered lines into single annotations.
  # A group includes:
  # - Uncovered lines (from LCOV)
  # - Blank lines
  # - Comments
  # - Non-executable code (not in LCOV)
  #
  # Groups are SPLIT by covered lines (lines with coverage > 0).
  # Exception: A covered line can be included if it's immediately followed by uncovered lines.

  def group_lines(source_lines, coverage_map) do
    source_lines
    |> Enum.map(fn {line_content, line_number} ->
      coverage =
        case {coverage_map, String.trim(line_content)} do
          {%{^line_number => 0}, _} -> :uncovered
          {%{^line_number => count}, _} when count > 0 -> :covered
          {%{}, ""} -> :blank_line
          {%{}, _} -> :not_executable
        end

      {coverage, line_number, line_content}
    end)
    |> build_uncovered_groups([])
    |> Enum.reverse()
  end

  # No more lines to process
  defp build_uncovered_groups([], groups), do: groups

  # Start a new group with this uncovered line
  defp build_uncovered_groups([{:uncovered, line_number, content} | rest], groups) do
    {group, remaining} = collect_group([{:uncovered, line_number, content} | rest], [])
    build_uncovered_groups(remaining, [group | groups])
  end

  # Skip non-uncovered lines (covered, blank, not_executable) when not in a group
  defp build_uncovered_groups([_line | rest], groups) do
    build_uncovered_groups(rest, groups)
  end

  defp collect_group([], current_group), do: {Enum.reverse(current_group), []}

  # Continue with uncovered line - always include
  defp collect_group([{:uncovered, line_number, _content} | rest], current_group) do
    collect_group(rest, [line_number | current_group])
  end

  # Include blank line - always include (they're just whitespace)
  defp collect_group([{:blank_line, line_number, _content} | rest], current_group) do
    collect_group(rest, [line_number | current_group])
  end

  # Include not executable line - always include (comments, function defs, etc.)
  defp collect_group([{:not_executable, line_number, _content} | rest], current_group) do
    collect_group(rest, [line_number | current_group])
  end

  # Hit a covered line - this SPLITS groups
  # Only include it if there's an uncovered line within 2 lines (very close)
  defp collect_group([{:covered, line_number, content} | rest], current_group) do
    if has_immediate_uncovered?(rest) do
      # Include this covered line and continue the group
      collect_group(rest, [line_number | current_group])
    else
      # Stop the group here - covered line creates a boundary
      {Enum.reverse(current_group), [{:covered, line_number, content} | rest]}
    end
  end

  # Check if there's an uncovered line very close (within 2 lines)
  # This allows a covered line to be included in a group if it's sandwiched
  # between uncovered lines (e.g., a single assertion in an untested function)
  defp has_immediate_uncovered?(lines) do
    has_immediate_uncovered?(lines, 0)
  end

  defp has_immediate_uncovered?([], _distance), do: false

  # Found an uncovered line immediately (no covered lines in between)
  defp has_immediate_uncovered?([{:uncovered, _line_number, _content} | _rest], distance)
       when distance == 0 do
    true
  end

  # Found an uncovered line but too far away
  defp has_immediate_uncovered?([{:uncovered, _line_number, _content} | _rest], _distance) do
    false
  end

  # Skip blank lines without counting distance
  defp has_immediate_uncovered?([{:blank_line, _line_number, _content} | rest], distance) do
    has_immediate_uncovered?(rest, distance)
  end

  # Skip not_executable lines without counting distance
  defp has_immediate_uncovered?([{:not_executable, _line_number, _content} | rest], distance) do
    has_immediate_uncovered?(rest, distance)
  end

  # Hit another covered line or exceeded distance - stop
  defp has_immediate_uncovered?([{:covered, _line_number, _content} | rest], distance) do
    has_immediate_uncovered?(rest, distance + 1)
  end
end
