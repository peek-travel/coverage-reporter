defmodule Mix.Tasks.CoverageReporterTest do
  use ExUnit.Case

  import Mix.Tasks.CoverageReporter, only: [build_params: 1]

  test "conclusion is success when there's coverage" do
    coverage_data = [coverage_item([1])]
    changed_files = changed_files(coverage_data)
    assert %{conclusion: "success"} = build_params(coverage_data: coverage_data, changed_files: changed_files)
  end

  test "conclusion is failure when there's not coverage" do
    coverage_data = [coverage_item([0])]
    changed_files = changed_files(coverage_data)
    assert %{conclusion: "failure"} = build_params(coverage_data: coverage_data, changed_files: changed_files)
  end

  test "doesn't fail when no coverage was calculated" do
    coverage_data = [coverage_item([nil])]
    changed_files = changed_files(coverage_data)
    assert %{conclusion: "success"} = build_params(coverage_data: coverage_data, changed_files: changed_files)
  end

  test "filters out nil coverage from head and tail" do
    coverage_data = [coverage_item([nil, nil, nil, 0, 1, 2, nil, nil])]
    changed_files = changed_files(coverage_data)
    assert %{output: %{text: text}} = build_params(coverage_data: coverage_data, changed_files: changed_files)
    assert text =~ "```diff\n  - line 4\n! line 5\n+ line 6\n  ```"
  end

  defp changed_files(coverage_data) do
    coverage_data
    |> get_in([Access.all(), "name"])
    |> Enum.join(" ")
  end

  defp coverage_item(coverage) do
    %{
      "name" => "path/to/file.ex",
      "coverage" => coverage,
      "source" => Enum.map(1..Enum.count(coverage), &"line #{&1}"),
    }
  end
end
