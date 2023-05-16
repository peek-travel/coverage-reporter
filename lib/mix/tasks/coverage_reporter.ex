defmodule Mix.Tasks.CoverageReporter do
  @moduledoc false
  use Mix.Task

  alias Mix.Tasks.Coveralls

  @shortdoc "Runs the test suite and generates a coverage reports"
  @preferred_cli_env :test

  def run(_) do
    run_tests()
    fetch_upstream_branch()
    params = build_params()
    post(params)
  end

  defp run_tests do
    Coveralls.do_run([], type: ["json", "html"])
  end

  defp fetch_upstream_branch do
    {_, 0} = System.cmd("git", ["fetch", "origin", config().base_branch, "--depth=1"])
  end

  defp get_changed_files do
    "git"
    |> System.cmd(["diff", "--name-only", "origin/#{config().base_branch}"])
    |> elem(0)
    |> String.split("\n")
    |> Enum.reject(&String.equivalent?(&1, ""))
  end

  defp read_coveralls_export do
    changed_files = get_changed_files()

    %{"source_files" => source_files} =
      "cover/excoveralls.json"
      |> File.read!()
      |> Jason.decode!()

    source_files
    |> Enum.map(&Map.put(&1, "source", String.split(&1["source"], "\n")))
    |> Enum.filter(&Enum.member?(changed_files, &1["name"]))
  end

  defp build_params do
    %{head_branch: head_branch, organization: organization, repository: repository} = config()

    source_files = read_coveralls_export()
    messages = Enum.flat_map(source_files, &create_groups/1)

    %{
      owner: organization,
      repo: repository,
      name: "Code Coverage",
      head_sha: head_branch,
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

        ```diff \
        #{message.diff} \
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
    |> Enum.drop_while(&is_nil/1)
    |> Enum.reverse()
    |> Enum.drop_while(&is_nil/1)
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce([[]], fn {num, index}, groups ->
      [current_group | rest] = groups
      current_group = Enum.concat([{num, index, Enum.at(source, index)}], current_group)
      [current_group | rest]
    end)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
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

  defp post(params) do
    :inets.start()
    :ssl.start()

    url = 'https://api.github.com/repos/SLAM-Carwash-Marketing/SlamE/check-runs'
    headers = [
      {'Authorization', 'Bearer #{config().github_token}'},
      {'Accept', 'application/vnd.github+json'},
      {'X-GitHub-Api-Version', '2022-11-28'},
      {'User-Agent', 'CoverageReporter'}
    ]
    content_type = 'application/json'
    body = Jason.encode!(params)

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

  defp config do
    %{
      head_branch: Application.fetch_env!(:coverage_reporter, :head_branch),
      base_branch: Application.fetch_env!(:coverage_reporter, :base_branch),
      repository: Application.fetch_env!(:coverage_reporter, :repository),
      organization: Application.fetch_env!(:coverage_reporter, :organization),
      github_token: Application.fetch_env!(:coverage_reporter, :github_token)
    }
  end
end
