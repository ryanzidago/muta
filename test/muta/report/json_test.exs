defmodule Muta.Report.JsonTest do
  use ExUnit.Case, async: true

  alias Muta.Mutant
  alias Muta.Report
  alias Muta.Report.Json

  defp mutant(file, line, outcome, function \\ "free_shipping?/1") do
    %Mutant{
      file: file,
      line: line,
      mutator: Muta.Mutator.Comparison,
      function: function,
      original: "cents > 5000",
      mutated: "cents >= 5000",
      outcome: outcome
    }
  end

  defp decode(report), do: report |> Json.encode() |> JSON.decode!()

  test "carries the score and every tally the terminal report prints" do
    report =
      Report.from_mutants(
        [mutant("a.ex", 2, :killed), mutant("a.ex", 3, :survived)],
        ["a.ex"],
        4,
        7
      )

    assert decode(report)["score"] == 50.0

    assert decode(report)["totals"] == %{
             "mutants" => 2,
             "killed" => 1,
             "survived" => 1,
             "accepted" => 0,
             "unstable" => 0,
             "invalid" => 0,
             "skipped" => 4,
             "in_type_guards" => 7
           }
  end

  test "describes each mutant by where it landed and what it changed" do
    report = Report.from_mutants([mutant("a.ex", 2, :survived)], ["a.ex"])

    assert decode(report)["mutants"] == [
             %{
               "file" => "a.ex",
               "line" => 2,
               "outcome" => "survived",
               "mutator" => "Comparison",
               "function" => "free_shipping?/1",
               "original" => "cents > 5000",
               "mutated" => "cents >= 5000"
             }
           ]
  end

  test "names the files it was given" do
    report = Report.from_mutants([mutant("b.ex", 2, :killed)], ["b.ex", "a.ex"])

    assert decode(report)["files"] == ["a.ex", "b.ex"]
  end

  test "names functions no test reached" do
    report =
      Report.from_mutants(
        [mutant("a.ex", 2, :survived, "unreached/1"), mutant("a.ex", 3, :killed, "pinned/1")],
        ["a.ex"]
      )

    assert decode(report)["unexercised"] == [%{"file" => "a.ex", "function" => "unreached/1"}]
  end

  test "encodes an empty run without inventing a shape" do
    decoded = decode(Report.from_mutants([], ["a.ex"]))

    assert decoded["score"] == 100.0
    assert decoded["mutants"] == []
    assert decoded["unexercised"] == []
  end
end
