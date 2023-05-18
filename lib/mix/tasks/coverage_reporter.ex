defmodule Mix.Tasks.CoverageReporter do
  @moduledoc false
  use Mix.Task

  alias Mix.Tasks.Coveralls

  @shortdoc "Runs the test suite and generates a coverage reports"
  @preferred_cli_env :test

  def run(args) do
    switches = [
      base_branch: :string,
      head_branch: :string,
      repository: :string,
      organization: :string,
      github_token: :string,
      changed_files: :string
    ]

    {opts, _, _} = OptionParser.parse(args, switches: switches)

    run_tests()
    post(opts)
  end

  defp run_tests() do
    Coveralls.do_run([], type: "json")
  end

  defp coverage_data do
    if Mix.Project.umbrella?() do
      Enum.flat_map(Mix.Project.apps_paths(), fn {_app, path} ->
        excoveralls_path = "#{path}/cover/excoveralls.json"
        if File.exists?(excoveralls_path) do
          excoveralls_path
          |> do_get_coverage_data()
          |> update_in([Access.all(), "name"], &"#{path}/#{&1}")
        else
          []
        end
      end)
    else
      do_get_coverage_data("cover/excoveralls.json")
    end
  end

  defp do_get_coverage_data(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.get("source_files")
      |> update_in([Access.all(), "source"], &String.split(&1, "\n"))
    else
      []
    end
  end

  def get_changed_files(opts) do
    if opts[:changed_files] do
      String.split(opts[:changed_files], " ", trim: true)
    else
      base_branch = Keyword.fetch!(opts, :base_branch)
      {changed_files, 0} = System.cmd("git", ["diff", "--name-only", "--diff-filter=ACMRT", "origin/#{base_branch}", "HEAD"])
      String.split(changed_files, "\n", trim: true)
    end
  end

  def read_coveralls_export(opts) do
    opts[:coverage_data] || coverage_data()
    |> Enum.filter(&Enum.member?(get_changed_files(opts), &1["name"]))
  end

  def build_params(opts) do
    source_files = read_coveralls_export(opts)
    messages = Enum.flat_map(source_files, &create_groups/1)

    %{
      owner: opts[:organization],
      repo: opts[:repository],
      name: "Code Coverage",
      head_sha: opts[:head_branch],
      status: "completed",
      conclusion: conclusion(source_files),
      output: %{
        title: "Code Coverage Report",
        summary: "Below is a summary of the missing coverages from the code coverage report",
        text: build_text_output(messages)
      }
    }
  end

  defp build_text_output(messages) do
    Enum.map_join(messages, "\n\n", fn message ->
      """
      <details>
        <summary>#{message.name}</summary>

        ```diff
        #{message.diff}
        ```
      </details>
      """
    end)
  end

  defp conclusion(source_files) do
    source_files
    |> get_in([Access.all(), "coverage"])
    |> List.flatten()
    |> Enum.find(&(&1 == 0))
    |> case do
      nil -> "success"
      _ -> "failure"
    end
  end

  defp create_groups(%{"coverage" => coverage, "name" => name, "source" => source}) do
    coverage
    |> Enum.with_index()
    |> Enum.drop_while(&is_nil(elem(&1, 0)))
    |> Enum.reverse()
    |> Enum.drop_while(&is_nil(elem(&1, 0)))
    |> Enum.reverse()
    |> Enum.reduce([[]], fn {num, index}, [current_group | rest] ->
      [Enum.concat([{num, index, Enum.at(source, index)}], current_group) | rest]
    end)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.reject(&Enum.empty?/1)
    |> Enum.map(fn group ->
      start_line = group |> List.first() |> elem(1)
      end_line = group |> List.last() |> elem(1)

      diff =
        Enum.map_join(group, "\n", fn
          {nil, _, source} -> "# #{source}"
          {0, _, source} -> "- #{source}"
          {1, _, source} -> "! #{source}"
          {coverage, _, source} when coverage > 1 -> "+ #{source}"
        end)

      %{name: name, start_line: start_line, end_line: end_line, diff: diff}
    end)
  end

  defp post(opts) do
    :inets.start()
    :ssl.start()

    url = 'https://api.github.com/repos/#{opts[:organization]}/#{opts[:repository]}/check-runs'
    headers = [
      {'Authorization', 'Bearer #{Keyword.fetch!(opts, :github_token)}'},
      {'Accept', 'application/vnd.github+json'},
      {'X-GitHub-Api-Version', '2022-11-28'},
      {'User-Agent', 'CoverageReporter'}
    ]
    content_type = 'application/json'
    body = Jason.encode!(build_params(opts))
    http_request_opts = [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    :httpc.request(:post, {url, headers, content_type, body}, http_request_opts, [])
  end
end
