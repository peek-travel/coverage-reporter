defmodule CoverageReporter do
  @moduledoc """
  Documentation for `CoverageReporter`.

  ### How to read an lcov file.

  Source: https://github.com/linux-test-project/lcov/issues/113#issuecomment-762335134

    - TN: test name
    - SF: source file path
    - FN: line number,function name
    - FNF:  number functions found
    - FNH: number hit
    - BRDA: branch data: line, block, (expressions,count)+
    - BRF: branches found
    - DA: line number, hit count
    - LF: lines found
    - LH:  lines hit.

  However, The LCOV files produced by excoveralls only include SF, DA, LF, LH, and end_of_record lines.
  """

  def main(opts) do
    config = get_config(opts)
    %{pull_number: pull_number, head_branch: head_branch, repository: repository} = config
    changed_files = get_changed_files(config)
    {total, module_results} = get_coverage_from_lcov_files(config)
    changed_module_results = module_results_for_changed_files(module_results, changed_files)
    title = "Code Coverage for ##{pull_number}"
    badge = create_total_coverage_badge(config, total)
    coverage_by_file = get_coverage_by_file(config, changed_module_results)
    annotations = create_annotations(config, changed_module_results, changed_files)
    summary = Enum.join(["#### #{title}", badge, coverage_by_file], "\n\n")

    params =
      %{
        name: "Code Coverage",
        head_sha: head_branch,
        status: "completed",
        conclusion: get_conclusion(config, total),
        output: %{
          title: title,
          # Maximum length for summary and text is 65535 characters.
          summary: String.slice(Enum.join([badge, coverage_by_file], "\n\n"), 0, 65_535),
          # 50 is the max number of annotations allowed by GitHub.
          annotations: Enum.take(annotations, 50)
        }
      }

    github_request(config, method: :post, url: "repos/#{repository}/check-runs", json: params)
    create_or_update_review_comment(config, summary)

    {:ok, params}
  end

  defp create_total_coverage_badge(config, total) do
    params = "logo=elixir&logoColor=purple&labelColor=white"
    url = "Total%20Coverage-#{format_percentage(total)}%25-#{get_conclusion_color(config, total)}"
    "![Total Coverage](https://img.shields.io/badge/#{url}?#{params})"
  end

  defp module_results_for_changed_files(module_results, changed_files) do
    changed_file_names = Enum.map(changed_files, fn %{file: file} -> file end)

    Enum.filter(module_results, fn {_, module_path, _} ->
      Enum.any?(changed_file_names, fn changed_file_name ->
        String.ends_with?(module_path, changed_file_name)
      end)
    end)
  end

  defp get_coverage_by_file(_config, []), do: nil

  defp get_coverage_by_file(config, module_results) do
    padding =
      module_results
      |> Enum.max_by(fn {_, name, _} -> String.length(name) end)
      |> elem(1)
      |> String.length()

    Enum.join(
      [
        "**Coverage by file**\n",
        "| Percentage | #{format_name("Module", padding)} |",
        "| ---------- | #{String.duplicate("-", padding)} |",
        "#{create_module_results(config, module_results, padding)}"
      ],
      "\n"
    )
  end

  defp get_coverage_from_lcov_files(config) do
    %{github_workspace: github_workspace, lcov_path: lcov_path} = config
    lcov_paths = Path.wildcard("#{github_workspace}/#{lcov_path}")
    table = :ets.new(__MODULE__, [:set, :private])

    module_results =
      Enum.reduce(lcov_paths, %{}, fn path, acc ->
        path
        |> File.stream!()
        |> Stream.map(&String.trim(&1))
        |> Stream.chunk_by(&(&1 == "end_of_record"))
        |> Stream.reject(&(&1 == ["end_of_record"]))
        |> Enum.reduce(acc, fn record, acc -> process_lcov_record(table, record, acc) end)
      end)
      |> Map.values()

    covered = :ets.select_count(table, [{{{:_, :_}, true}, [], [true]}])
    not_covered = :ets.select_count(table, [{{{:_, :_}, false}, [], [true]}])
    total = percentage(covered, not_covered)

    {total, module_results}
  end

  defp process_lcov_record(table, record, acc) do
    "SF:" <> path = Enum.find(record, &String.starts_with?(&1, "SF:"))

    coverage_by_line =
      record
      |> Enum.filter(fn line -> String.starts_with?(line, "DA:") end)
      |> Enum.map(fn "DA:" <> value ->
        [line_number, count] =
          value
          |> String.split(",")
          |> Enum.map(&String.to_integer(&1))

        covered = :ets.select_count(table, [{{{path, line_number}, true}, [], [true]}])
        insert_line_coverage(table, count, path, line_number)

        {line_number, count + covered}
      end)

    covered = :ets.select_count(table, [{{{path, :_}, true}, [], [true]}])
    not_covered = :ets.select_count(table, [{{{path, :_}, false}, [], [true]}])
    Map.put(acc, path, {percentage(covered, not_covered), path, coverage_by_line})
  end

  defp insert_line_coverage(table, count, path, line_number) do
    covered_count = :ets.select_count(table, [{{{path, line_number}, true}, [], [true]}])

    if count == 0 and covered_count == 0 do
      :ets.insert_new(table, {{path, line_number}, false})
    else
      Enum.each(1..count, fn _ -> :ets.insert(table, {{path, line_number}, true}) end)
    end
  end

  defp get_changed_files(config) do
    %{repository: repository, pull_number: pull_number} = config

    {:ok, 200, files} =
      github_request_all(config, "repos/#{repository}/pulls/#{pull_number}/files")

    files
    |> Enum.reject(&String.equivalent?(&1["status"], "removed"))
    |> Enum.map(fn file ->
      %{file: file["filename"], changed_lines: extract_changed_lines(file["patch"])}
    end)
  end

  defp create_module_results(config, module_results, padding) do
    module_results
    |> Enum.map(fn {percentage, name, coverage} ->
      name =
        if is_nil(config.lcov_path_prefix) or config.lcov_path_prefix == "" do
          name
        else
          String.replace_leading(name, config.lcov_path_prefix, "")
        end

      {percentage, name, coverage}
    end)
    |> Enum.map_join("\n", &display(elem(&1, 0), elem(&1, 1), padding))
  end

  defp percentage(0, 0), do: 100.0
  defp percentage(covered, not_covered), do: covered / (covered + not_covered) * 100

  defp display(percentage, name, padding) do
    "| #{format_name(format_percentage(percentage) <> "%", 10)} | #{format_name(name, padding)} |"
  end

  defp format_percentage(number) do
    number =
      number
      |> Float.round(2)
      |> Float.to_string()

    number
  end

  defp format_name(name, padding) when is_binary(name) do
    String.pad_trailing(name, padding, " ")
  end

  defp get_conclusion(config, total) do
    if total >= config.coverage_threshold do
      "success"
    else
      "neutral"
    end
  end

  defp get_conclusion_color(config, total) do
    if total >= config.coverage_threshold do
      "green"
    else
      "yellow"
    end
  end

  defp create_or_update_review_comment(config, summary) do
    %{repository: repository, pull_number: pull_number} = config

    {:ok, 200, reviews} =
      github_request_all(config, "repos/#{repository}/pulls/#{pull_number}/reviews")

    review = Enum.find(reviews, &(&1["body"] =~ "Code Coverage for ##{pull_number}"))

    if is_nil(review) do
      github_request(config,
        method: :post,
        url: "repos/#{repository}/pulls/#{pull_number}/reviews",
        json: %{body: summary, event: "COMMENT"}
      )
    else
      github_request(
        config,
        method: :put,
        url: "repos/#{repository}/pulls/#{pull_number}/reviews/#{review["id"]}",
        json: %{body: summary}
      )
    end
  end

  defp create_annotations(config, changed_module_results, changed_files) do
    %{github_workspace: github_workspace} = config

    Enum.flat_map(changed_module_results, fn {_percentage, module_path, coverage_by_line} ->
      %{file: file, changed_lines: changed_lines} =
        Enum.find(changed_files, fn %{file: file} -> String.ends_with?(module_path, file) end)

      source_code_lines =
        github_workspace
        |> Path.join(file)
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map(fn {line, index} -> [nil, line, index] end)

      source_code =
        coverage_by_line
        |> Enum.reduce(source_code_lines, fn {line_number, count}, source_code_lines ->
          List.update_at(
            source_code_lines,
            line_number - 1,
            &[count, Enum.at(&1, 1), Enum.at(&1, 2)]
          )
        end)
        |> Enum.map(&add_source_code_line/1)

      coverage_by_line
      |> Enum.filter(fn {_line_number, count} -> count == 0 end)
      |> Enum.map(fn {line_number, _} -> line_number end)
      |> Enum.reduce(_groups = [], &add_line_to_groups/2)
      |> Enum.reduce(
        _annotations = [],
        &do_create_annotations(&1, &2, changed_lines, file, source_code)
      )
    end)
  end

  defp do_create_annotations(line_number_group, annotations, changed_lines, file, source_code) do
    end_line = List.first(line_number_group)
    start_line = List.last(line_number_group)

    add_annotation? =
      Enum.any?(changed_lines, &(&1 >= start_line and &1 <= end_line))

    if add_annotation? do
      annotation =
        Map.merge(
          %{
            title: "Code Coverage",
            start_line: start_line,
            end_line: end_line,
            annotation_level: "warning",
            path: file
          },
          create_annotation_message(start_line, end_line, source_code)
        )

      [annotation] ++ annotations
    else
      annotations
    end
  end

  defp add_source_code_line([nil, line, line_number]) do
    "#{String.duplicate(" ", 5)} #{String.pad_trailing("#{line_number}", 3)} #{line}"
  end

  defp add_source_code_line([count, line, line_number]) do
    "#{String.pad_trailing("#{count}", 5, ".")} #{String.pad_trailing("#{line_number}", 3)} #{line}"
  end

  defp create_annotation_message(start_line, end_line, source_code) do
    source_code =
      source_code
      |> Enum.slice((start_line - 1)..(end_line - 1))
      |> Enum.join("\n")

    %{
      message: "Lines #{start_line} to #{end_line} are not covered by tests.",
      raw_details: source_code
    }
  end

  defp add_line_to_groups(line_number, groups) do
    group =
      cond do
        Enum.empty?(groups) ->
          [[line_number]]

        [current_group | remaining_groups] = groups ->
          previous_line_number = List.first(current_group)

          if line_number - previous_line_number < 4 do
            [[line_number] ++ current_group] ++ remaining_groups
          else
            [[line_number]] ++ groups
          end
      end

    Enum.sort(group)
  end

  defp extract_changed_lines(nil), do: []

  defp extract_changed_lines(patch) do
    patch
    |> String.split("\n")
    |> Enum.reduce({nil, []}, fn line, {current_line, changes} ->
      case Regex.scan(~r/@@ -\d+,?\d* \+(\d+),?\d* @@/, line) do
        [[_ | [start_line]]] ->
          {String.to_integer(start_line), changes}

        _ ->
          add_changed_line(line, current_line, changes)
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp add_changed_line(_line, nil, changes) do
    {nil, changes}
  end

  defp add_changed_line(line, current_line, changes) do
    case line do
      "+" <> _ ->
        {current_line + 1, [current_line | changes]}

      "-" <> _ ->
        {current_line, changes}

      " " <> _ ->
        {current_line + 1, changes}

      _ ->
        {nil, changes}
    end
  end

  defp github_request_all(config, path, params \\ %{page: 1}, accumulator \\ []) do
    case github_request(config, method: :get, url: path, params: params) do
      {200, []} ->
        {:ok, 200, accumulator}

      {200, results} ->
        params = Map.put(params, :page, params[:page] + 1)
        github_request_all(config, path, params, results ++ accumulator)
    end
  end

  defp github_request(config, opts) do
    %{
      github_api_url: github_api_url,
      github_token: github_token
    } = config

    headers = [
      {:authorization, "Bearer #{github_token}"},
      {:accept, "application/vnd.github+json"},
      {:x_github_api_version, "2022-11-28"},
      {:user_agent, "CoverageReporter"}
    ]

    options =
      Keyword.merge(opts,
        base_url: github_api_url,
        headers: headers,
        connect_options: [transport_opts: [cacertfile: "/cacerts.pem"]]
      )

    request = Req.new(options)

    {_request, %{status: status, body: body}} = Req.request(request)

    {status, body}
  end

  defp get_config(opts) do
    %{
      coverage_threshold: coverage_threshold(opts),
      lcov_path: lcov_path(opts),
      head_branch: head_branch(opts),
      repository: repository(opts),
      github_workspace: github_workspace(opts),
      github_token: github_token(opts),
      github_api_url: github_api_url(opts),
      pull_number: pull_number(opts),
      lcov_path_prefix: lcov_path_prefix(opts)
    }
  end

  defp coverage_threshold(opts) do
    value = opts[:coverage_threshold] || System.get_env("INPUT_COVERAGE_THRESHOLD", "80")
    String.to_integer(value)
  end

  defp lcov_path(opts), do: opts[:input_lcov_path] || System.get_env("INPUT_LCOV_PATH")
  defp head_branch(opts), do: opts[:github_head_ref] || System.get_env("GITHUB_HEAD_REF")
  defp repository(opts), do: opts[:github_repository] || System.get_env("GITHUB_REPOSITORY")
  defp github_workspace(opts), do: opts[:github_workspace] || System.get_env("GITHUB_WORKSPACE")
  defp github_token(opts), do: opts[:input_github_token] || System.get_env("INPUT_GITHUB_TOKEN")
  defp github_api_url(opts), do: opts[:github_api_url] || System.get_env("GITHUB_API_URL")

  defp lcov_path_prefix(opts),
    do: opts[:lcov_path_prefix] || System.get_env("INPUT_LCOV_PATH_PREFIX")

  defp pull_number(opts) do
    ["refs", "pull", pr_number, "merge"] =
      (opts[:github_ref] || System.get_env("GITHUB_REF")) |> String.split("/")

    pr_number
  end
end
