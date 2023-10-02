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

  def run(pull_number, repository, github_token, head_branch) do
    changed_files = get_changed_files(repository, pull_number, github_token)
    {total, module_results} = get_coverage_from_lcov_files()
    changed_module_results = module_results_for_changed_files(module_results, changed_files)

    title = "Code Coverage for ##{pull_number}"
    badge = create_total_coverage_badge(total)
    coverage_by_file = get_coverage_by_file(changed_module_results)
    annotations = create_annotations(changed_module_results, changed_files)

    summary = Enum.join(["#### #{title}", badge, coverage_by_file], "\n\n")

    params = %{
      name: "Code Coverage",
      head_sha: head_branch,
      status: "completed",
      conclusion: get_conclusion(total),
      output: %{
        title: title,
        # Maximum length for summary and text is 65535 characters.
        summary: String.slice(Enum.join([badge, coverage_by_file], "\n\n"), 0, 65_535),
        # 50 is the max number of annotations allowed by GitHub.
        annotations: Enum.take(annotations, 50)
      }
    }

    github_request(:post, "#{repository}/check-runs", github_token, params)
    create_or_update_review_comment(repository, pull_number, summary, github_token)

    :ok
  end

  defp create_total_coverage_badge(total) do
    params = "logo=elixir&logoColor=purple&labelColor=white"
    url = "Total%20Coverage-#{format_percentage(total)}%25-#{get_conclusion_color(total)}"
    "![Total Coverage](https://img.shields.io/badge/#{url}?#{params})"
  end

  defp module_results_for_changed_files(module_results, changed_files) do
    changed_file_names = Enum.map(changed_files, fn %{file: file} -> file end)

    Enum.filter(module_results, fn {_, module_path, _} ->
      Enum.any?(changed_file_names, fn changed_file_name ->
        String.ends_with?(changed_file_name, module_path)
      end)
    end)
  end

  defp get_coverage_by_file([]), do: nil

  defp get_coverage_by_file(module_results) do
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
        "#{create_module_results(module_results, padding)}"
      ],
      "\n"
    )
  end

  defp get_coverage_from_lcov_files do
    project_path = System.get_env("GITHUB_WORKSPACE")
    lcov_paths = Path.wildcard("#{project_path}/cover/**-lcov.info")
    table = :ets.new(__MODULE__, [:set, :private])

    module_results =
      Enum.flat_map(lcov_paths, fn path ->
        path
        |> File.stream!()
        |> Stream.map(&String.trim(&1))
        |> Stream.chunk_by(&(&1 == "end_of_record"))
        |> Stream.reject(&(&1 == ["end_of_record"]))
        |> Stream.map(fn record -> process_lcov_record(table, record) end)
      end)

    covered = :ets.select_count(table, [{{{:_, :_}, true}, [], [true]}])
    not_covered = :ets.select_count(table, [{{{:_, :_}, false}, [], [true]}])
    total = percentage(covered, not_covered)

    {total, module_results}
  end

  defp process_lcov_record(table, record) do
    "SF:" <> path = Enum.find(record, &String.starts_with?(&1, "SF:"))

    coverage_by_line =
      record
      |> Enum.filter(fn line -> String.starts_with?(line, "DA:") end)
      |> Enum.map(fn "DA:" <> value ->
        [line_number, count] =
          value
          |> String.split(",")
          |> Enum.map(&String.to_integer(&1))

        if count == 0 do
          :ets.insert(table, {{path, line_number}, false})
        else
          Enum.each(1..count, fn _ -> :ets.insert(table, {{path, line_number}, true}) end)
        end

        {line_number, count}
      end)

    covered = :ets.select_count(table, [{{{path, :_}, true}, [], [true]}])
    not_covered = :ets.select_count(table, [{{{path, :_}, false}, [], [true]}])
    {percentage(covered, not_covered), path, coverage_by_line}
  end

  defp get_changed_files(repository, pull_number, github_token) do
    {:ok, 200, files} =
      github_request_all("#{repository}/pulls/#{pull_number}/files", github_token)

    files
    |> Enum.reject(&String.equivalent?(&1["status"], "removed"))
    |> Enum.map(fn file ->
      %{file: file["filename"], changed_lines: extract_changed_lines(file["patch"])}
    end)
  end

  defp create_module_results([], padding),
    do: "| No Changes | #{String.duplicate(" ", padding)} |"

  defp create_module_results(module_results, padding) do
    Enum.map_join(module_results, "\n", &display(elem(&1, 0), elem(&1, 1), padding))
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

  defp get_conclusion(total) do
    if total >= 80 do
      "success"
    else
      "neutral"
    end
  end

  defp get_conclusion_color(total) do
    if total >= 80 do
      "green"
    else
      "yellow"
    end
  end

  defp create_or_update_review_comment(repository, pull_number, summary, github_token) do
    {:ok, 200, reviews} =
      github_request_all("#{repository}/pulls/#{pull_number}/reviews", github_token)

    review = Enum.find(reviews, &(&1["body"] =~ "Code Coverage for ##{pull_number}"))

    if is_nil(review) do
      github_request(:post, "#{repository}/pulls/#{pull_number}/reviews", github_token, %{
        body: summary,
        event: "COMMENT"
      })
    else
      github_request(
        :put,
        "#{repository}/pulls/#{pull_number}/reviews/#{review["id"]}",
        github_token,
        %{
          body: summary
        }
      )
    end
  end

  defp create_annotations(changed_module_results, changed_files) do
    Enum.flat_map(changed_module_results, fn {_percentage, module_path, coverage_by_line} ->
      project_path = System.get_env("GITHUB_WORKSPACE")

      %{file: file, changed_lines: changed_lines} =
        Enum.find(changed_files, fn %{file: file} -> String.ends_with?(file, module_path) end)

      source_code_lines =
        "#{project_path}/#{file}"
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(0)
        |> Enum.map(fn {line, index} -> [nil, line, index] end)

      source_code =
        coverage_by_line
        |> Enum.reduce(source_code_lines, fn {line_number, count}, source_code_lines ->
          List.update_at(source_code_lines, line_number, &[count, Enum.at(&1, 1), Enum.at(&1, 2)])
        end)
        |> Enum.map(&add_source_code_line/1)

      coverage_by_line
      |> Enum.filter(fn {_line_number, count} -> count == 0 end)
      |> Enum.map(fn {line_number, _} -> line_number end)
      |> Enum.reduce(_groups = [], &add_line_to_groups/2)
      |> Enum.reduce(_annotations = [], fn line_number_group, annotations ->
        end_line = List.first(line_number_group)
        start_line = List.last(line_number_group)
        add_annotation? = Enum.any?(changed_lines, &(&1 >= start_line and &1 <= end_line))

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
      end)
    end)
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
      |> Enum.slice((start_line - 5)..(end_line + 5))
      |> Enum.join("\n")

    %{
      message: "Lines #{start_line} to #{end_line} are not covered by tests.",
      raw_details: source_code
    }
  end

  defp add_line_to_groups(line_number, groups) do
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
  end

  defp extract_changed_lines(patch) do
    patch
    |> String.split("\n")
    |> Enum.reduce({nil, []}, fn line, {current_line, changes} ->
      case Regex.scan(~r/@@ -\d+,?\d* \+(\d+),?\d* @@/, line) do
        [[_ | [start_line]]] ->
          {String.to_integer(start_line), changes}

        _ ->
          case line do
            "+" <> _ -> {current_line + 1, [current_line | changes]}
            "-" <> _ -> {current_line, changes}
            " " <> _ -> {current_line + 1, changes}
            _ -> {nil, changes}
          end
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp github_request_all(path, github_token, params \\ %{page: 1}, accumulator \\ []) do
    case github_request(:get, path, github_token, params) do
      {:ok, 200, []} ->
        {:ok, 200, accumulator}

      {:ok, 200, results} ->
        params = Map.put(params, :page, params[:page] + 1)
        github_request_all(path, github_token, params, results ++ accumulator)

      {:ok, status_code, result} ->
        {:ok, status_code, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp github_request(method, path, github_token, params) do
    :inets.start()
    :ssl.start()

    url = ~c"https://api.github.com/repos/#{path}"

    headers = [
      {~c"Authorization", ~c"Bearer #{github_token}"},
      {~c"Accept", ~c"application/vnd.github+json"},
      {~c"X-GitHub-Api-Version", ~c"2022-11-28"},
      {~c"User-Agent", ~c"CoverageReporter"}
    ]

    request =
      case method do
        :get ->
          {~c"#{url}?#{URI.encode_query(params)}", headers}

        :post ->
          {url, headers, ~c"application/json", Jason.encode!(params)}

        :put ->
          {url, headers, ~c"application/json", Jason.encode!(params)}
      end

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    case :httpc.request(method, request, [ssl: ssl], []) do
      {:ok, {{_http_version, status_code, _response_string}, _headers, body}} ->
        {:ok, status_code, Jason.decode!(body)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
