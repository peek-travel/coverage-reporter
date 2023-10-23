defmodule CoverageReporterTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    {:ok, workspace} = Briefly.create(directory: true)

    config = [
      coverage_threshold: "80",
      input_lcov_path: "lcov.info",
      github_ref: "refs/pull/1/merge",
      input_github_token: "github-token",
      github_workspace: workspace,
      github_api_url: "http://localhost:#{bypass.port()}",
      github_repository: "owner/repo",
      github_head_ref: "feature-branch"
    ]

    %{bypass: bypass, config: config}
  end

  test "with a single uncovered line", ctx do
    %{bypass: bypass, config: config} = ctx

    setup_changes(
      bypass,
      config,
      path: "path/to/file",
      status: "added",
      changed_lines: [1, 2, 3, 4, 5, 6, 7, 8],
      patch: "@@ -0,0 +1,8 @@\n+one\n+two\n+three\n+four\n+five\n+six\n+seven\n+eight\n",
      lcov:
        "TN:\nSF:path/to/file\nDA:1,1\nDA:2,1\nDA:3,1\nDA:4,0\nDA:5,1\nDA:6,1\nDA:7,1\nDA:8,1\nend_of_record",
      source_code: "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight"
    )

    assert {:ok,
            %{
              conclusion: "success",
              output: %{
                summary: summary,
                annotations: [
                  %{
                    start_line: 4,
                    end_line: 4,
                    raw_details: "0.... 4   four"
                  }
                ]
              }
            }} = CoverageReporter.run(config)

    assert summary =~ "87.5%"
  end

  test "with a two uncovered lines", ctx do
    %{bypass: bypass, config: config} = ctx

    setup_changes(
      bypass,
      config,
      path: "path/to/file",
      status: "added",
      changed_lines: [1, 2, 3, 4, 5, 6, 7, 8],
      patch: "@@ -0,0 +1,8 @@\n+one\n+two\n+three\n+four\n+five\n+six\n+seven\n+eight\n",
      lcov:
        "TN:\nSF:path/to/file\nDA:1,1\nDA:2,1\nDA:3,1\nDA:4,0\nDA:5,0\nDA:6,1\nDA:7,1\nDA:8,1\nend_of_record",
      source_code: "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight"
    )

    assert {:ok,
            %{
              conclusion: "neutral",
              output: %{
                summary: summary,
                annotations: [
                  %{
                    start_line: 4,
                    end_line: 5,
                    raw_details: "0.... 4   four\n0.... 5   five"
                  }
                ]
              }
            }} =
             CoverageReporter.run(config)

    assert summary =~ "75.0%"
  end

  test "with disjointed uncovered lines", ctx do
    %{bypass: bypass, config: config} = ctx

    setup_changes(
      bypass,
      config,
      path: "path/to/file",
      status: "added",
      changed_lines: [1, 2, 3, 4, 5, 6, 7, 8],
      patch: "@@ -0,0 +1,8 @@\n+one\n+two\n+three\n+four\n+five\n+six\n+seven\n+eight\n",
      lcov:
        "TN:\nSF:path/to/file\nDA:1,1\nDA:2,1\nDA:3,1\nDA:4,0\nDA:5,1\nDA:6,0\nDA:7,1\nDA:8,1\nend_of_record",
      source_code: "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight"
    )

    assert {:ok,
            %{
              conclusion: "neutral",
              output: %{
                summary: summary,
                annotations: [
                  %{
                    start_line: 4,
                    end_line: 6,
                    raw_details: "0.... 4   four\n1.... 5   five\n0.... 6   six"
                  }
                ]
              }
            }} = CoverageReporter.run(config)

    assert summary =~ "75.0%"
  end

  test "with disjointed uncovered lines creating multiple annotations", ctx do
    %{bypass: bypass, config: config} = ctx

    setup_changes(
      bypass,
      config,
      path: "path/to/file",
      status: "added",
      changed_lines: [1, 2, 3, 4, 5, 6, 7, 8],
      patch: "@@ -0,0 +1,8 @@\n+one\n+two\n+three\n+four\n+five\n+six\n+seven\n+eight\n",
      lcov:
        "TN:\nSF:path/to/file\nDA:1,0\nDA:2,1\nDA:3,1\nDA:4,1\nDA:5,1\nDA:6,1\nDA:7,1\nDA:8,0\nend_of_record",
      source_code: "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight"
    )

    assert {:ok,
            %{
              conclusion: "neutral",
              output: %{
                summary: summary,
                annotations: [
                  %{
                    start_line: 8,
                    end_line: 8,
                    raw_details: "0.... 8   eight"
                  },
                  %{
                    start_line: 1,
                    end_line: 1,
                    raw_details: "0.... 1   one"
                  }
                ]
              }
            }} = CoverageReporter.run(config)

    assert summary =~ "75.0%"
  end

  test "without changed files", ctx do
    %{bypass: bypass, config: config} = ctx

    setup_changes(
      bypass,
      config,
      path: "path/to/file",
      status: "added",
      changed_lines: [],
      patch: "",
      lcov: "",
      source_code: "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight"
    )

    assert {:ok,
            %{
              conclusion: "success",
              output: %{
                annotations: []
              }
            }} = CoverageReporter.run(config)
  end

  test "without annotations", ctx do
    %{bypass: bypass, config: config} = ctx

    setup_changes(
      bypass,
      config,
      path: "path/to/file",
      status: "added",
      changed_lines: [1],
      patch: "@@ -0,0 +1,1 @@\n+one",
      lcov: "TN:\nSF:path/to/file\nDA:1,1\nend_of_record",
      source_code: "one",
      new_pull_request?: true
    )

    assert {:ok,
            %{
              conclusion: "success",
              output: %{
                summary: summary,
                annotations: []
              }
            }} = CoverageReporter.run(config)

    assert summary =~ "100.0%"
  end

  test "with deletions and empty lines", ctx do
    %{bypass: bypass, config: config} = ctx

    setup_changes(
      bypass,
      config,
      path: "path/to/file",
      status: "added",
      changed_lines: [1],
      patch: "@@ -1,1 +1,1 @@\n-one\n+two\n ",
      lcov: "TN:\nSF:path/to/file\nDA:1,1\nend_of_record",
      source_code: "one",
      new_pull_request?: true
    )

    assert {:ok,
            %{
              conclusion: "success",
              output: %{
                summary: summary,
                annotations: []
              }
            }} = CoverageReporter.run(config)

    assert summary =~ "100.0%"
  end

  test "lcov path prefix", ctx do
    %{bypass: bypass, config: config} = ctx

    config = Keyword.put(config, :lcov_path_prefix, "system/")

    setup_changes(
      bypass,
      config,
      path: "path/to/file",
      status: "added",
      changed_lines: [1, 2, 3],
      patch: "@@ -0,0 +1,8 @@\n+one\n+two\n+three",
      lcov: "TN:\nSF:system/path/to/file\nDA:1,1\nDA:2,1\nDA:3,1\nend_of_record",
      source_code: "one\ntwo\nthree"
    )

    assert {:ok, %{output: %{summary: summary}}} = CoverageReporter.run(config)

    assert summary =~ " path/to/file "
  end

  defp setup_changes(bypass, config, opts) do
    changed_lines = Keyword.fetch!(opts, :changed_lines)
    patch = Keyword.fetch!(opts, :patch)
    path = Keyword.fetch!(opts, :path)
    status = Keyword.get(opts, :status, "added")
    lcov = Keyword.fetch!(opts, :lcov)
    source_code = Keyword.fetch!(opts, :source_code)
    new_pull_request? = Keyword.get(opts, :new_pull_request?, false)
    pull_number = config[:github_ref] |> String.split("/") |> Enum.at(2)

    Bypass.expect(bypass, "GET", "repos/owner/repo/pulls/#{pull_number}/files", fn conn ->
      if conn.params["page"] == "1" do
        json(conn, 200, [
          %{
            status: status,
            changed_lines: changed_lines,
            filename: path,
            patch: patch
          }
        ])
      else
        json(conn, 200, [])
      end
    end)

    Bypass.expect(bypass, "POST", "repos/owner/repo/check-runs", &json(&1, 200, []))

    Bypass.expect(bypass, "GET", "repos/owner/repo/pulls/#{pull_number}/reviews", fn conn ->
      if conn.params["page"] == "1" and new_pull_request? do
        json(conn, 200, [%{body: "Code Coverage for ##{pull_number}"}])
      else
        json(conn, 200, [])
      end
    end)

    if new_pull_request? do
      Bypass.expect(
        bypass,
        "PUT",
        "repos/owner/repo/pulls/#{pull_number}/reviews",
        &json(&1, 200, [])
      )
    else
      Bypass.expect(
        bypass,
        "POST",
        "repos/owner/repo/pulls/#{pull_number}/reviews",
        &json(&1, 200, [])
      )
    end

    File.write!(config[:github_workspace] <> "/" <> config[:input_lcov_path], lcov)

    directory =
      String.split(path, "/")
      |> Enum.reverse()
      |> Enum.drop(1)
      |> Enum.reverse()
      |> Enum.join("/")

    File.mkdir_p!(config[:github_workspace] <> "/" <> directory)
    File.write!(config[:github_workspace] <> "/" <> path, source_code)
  end

  defp json(conn, status, data) do
    conn =
      case Plug.Conn.get_resp_header(conn, "content-type") do
        [] ->
          Plug.Conn.put_resp_content_type(conn, "application/json")

        _ ->
          conn
      end

    Plug.Conn.send_resp(conn, status, Jason.encode_to_iodata!(data))
  end
end
