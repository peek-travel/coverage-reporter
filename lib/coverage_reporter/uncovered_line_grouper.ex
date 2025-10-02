defmodule CoverageReporter.UncoveredLineGrouper do
  @moduledoc false

  # Groups consecutive uncovered lines into single annotations.
  def group_lines(source_lines, coverage_map) do
    source_lines
    |> Enum.map(fn {line_content, line_number} ->
      coverage_count = Map.get(coverage_map, line_number, :no_coverage)
      uncovered? = coverage_count == 0
      # Only treat blank lines as bridgeable if they don't have explicit coverage data
      blank_line? = coverage_count == :no_coverage and String.trim(line_content) == ""
      {line_number, line_content, uncovered?, blank_line?}
    end)
    |> build_uncovered_groups([])
    |> Enum.reverse()
  end

  # No more lines to process
  defp build_uncovered_groups([], groups), do: groups

  # Start a new group with this uncovered line
  defp build_uncovered_groups([{line_number, content, true, blank_line?} | rest], groups) do
    {group, remaining} = collect_group([{line_number, content, true, blank_line?} | rest], [])
    build_uncovered_groups(remaining, [group | groups])
  end

  # Skip covered lines
  defp build_uncovered_groups([_line | rest], groups) do
    build_uncovered_groups(rest, groups)
  end

  defp collect_group([], current_group), do: {Enum.reverse(current_group), []}

  # Continue with uncovered line
  defp collect_group([{line_number, _content, true, _blank_line?} | rest], current_group) do
    collect_group(rest, [line_number | current_group])
  end

  # Include blank line in group and continue
  defp collect_group([{line_number, _content, false, true} | rest], current_group) do
    collect_group(rest, [line_number | current_group])
  end

  # Hit a covered, non-fuzzy line - check if we should include it for fuzziness
  defp collect_group([{line_number, content, false, false} | rest], current_group) do
    if look_ahead_for_uncovered?(rest, 1) do
      collect_group(rest, [line_number | current_group])
    else
      {Enum.reverse(current_group), [{line_number, content, false, false} | rest]}
    end
  end

  # Look ahead to see if there are uncovered lines within max_distance
  defp look_ahead_for_uncovered?(lines, distance) do
    case {lines, distance} do
      # No more lines to check
      {[], _} ->
        false

      # Found an uncovered line within distance
      {[{_line_number, _content, true, _blank_line?} | _rest], distance} when distance <= 1 ->
        true

      # Skip blank lines and continue looking
      {[{_line_number, _content, false, true} | rest], distance} when distance <= 1 ->
        look_ahead_for_uncovered?(rest, distance)

      # Distance exceeded or other cases
      _ ->
        false
    end
  end
end
