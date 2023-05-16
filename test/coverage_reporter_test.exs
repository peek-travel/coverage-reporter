defmodule CoverageReporterTest do
  use ExUnit.Case
  doctest CoverageReporter

  test "greets the world" do
    assert CoverageReporter.hello() == :world
  end
end
