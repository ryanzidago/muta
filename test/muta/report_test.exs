defmodule Muta.ReportTest do
  use ExUnit.Case, async: true

  alias Muta.Mutant
  alias Muta.Report

  defp mutant(file, line, outcome) do
    %Mutant{
      file: file,
      line: line,
      mutator: Muta.Mutator.Comparison,
      function: "check/1",
      original: "n > #{line}",
      mutated: "n >= #{line}",
      outcome: outcome
    }
  end

  defp in_function(file, function, outcome) do
    %Mutant{
      file: file,
      line: 1,
      mutator: Muta.Mutator.Comparison,
      function: function,
      original: "n > 1",
      mutated: "n >= 1",
      outcome: outcome
    }
  end

  test "counts nothing as skipped or suppressed unless told about it" do
    report = Report.from_mutants([mutant("a.ex", 2, :killed)], ["a.ex"])

    assert report.skipped == 0
    assert report.in_type_guards == 0
  end

  test "carries the mutants a type guard suppressed, since a silent drop flatters the score" do
    report = Report.from_mutants([mutant("a.ex", 2, :killed)], ["a.ex"], 0, 5)

    assert report.in_type_guards == 5
  end

  test "names a function whose every mutant survived" do
    report =
      Report.from_mutants(
        [
          in_function("a.ex", "unreached/1", :survived),
          in_function("a.ex", "unreached/1", :survived),
          in_function("a.ex", "pinned/1", :survived),
          in_function("a.ex", "pinned/1", :killed)
        ],
        ["a.ex"]
      )

    assert Report.unexercised(report) == [{"a.ex", "unreached/1"}]
  end

  test "names a function with no kills even when some of its mutants never ran" do
    report =
      Report.from_mutants(
        [
          in_function("a.ex", "unreached/1", :survived),
          in_function("a.ex", "unreached/1", :invalid)
        ],
        ["a.ex"]
      )

    assert Report.unexercised(report) == [{"a.ex", "unreached/1"}]
  end

  test "names no function when nothing survived" do
    report = Report.from_mutants([in_function("a.ex", "pinned/1", :killed)], ["a.ex"])

    assert Report.unexercised(report) == []
  end

  test "counts each outcome and scores the ones that produced a verdict" do
    report =
      Report.from_mutants(
        [
          mutant("a.ex", 1, :killed),
          mutant("a.ex", 2, :killed),
          mutant("a.ex", 3, :survived),
          mutant("a.ex", 4, :unstable),
          mutant("a.ex", 5, :invalid)
        ],
        ["a.ex"]
      )

    assert report.killed == 2
    assert report.survived == 1
    assert report.unstable == 1
    assert report.invalid == 1
    assert report.score == 66.67
  end

  test "leaves unstable and invalid mutants out of the score" do
    report =
      Report.from_mutants(
        [mutant("a.ex", 1, :killed), mutant("a.ex", 2, :unstable), mutant("a.ex", 3, :invalid)],
        ["a.ex"]
      )

    assert report.score == 100.0
  end

  test "scores a file nothing could be mutated in at full marks, having judged nothing" do
    assert Report.from_mutants([], ["a.ex"]).score == 100.0
  end

  test "lists survivors and unstable mutants apart, each in file and line order" do
    report =
      Report.from_mutants(
        [
          mutant("b.ex", 9, :survived),
          mutant("a.ex", 4, :unstable),
          mutant("a.ex", 2, :survived),
          mutant("a.ex", 7, :killed)
        ],
        ["a.ex", "b.ex"]
      )

    assert Enum.map(Report.survivors(report), &{&1.file, &1.line}) == [{"a.ex", 2}, {"b.ex", 9}]
    assert Enum.map(Report.unstable(report), &{&1.file, &1.line}) == [{"a.ex", 4}]
  end

  test "gives every named file a line of its own, in name order" do
    report =
      Report.from_mutants(
        [mutant("b.ex", 1, :killed), mutant("a.ex", 1, :survived)],
        ["b.ex", "a.ex"]
      )

    assert [{"a.ex", first}, {"b.ex", second}] = Report.by_file(report)
    assert first.survived == 1
    assert second.killed == 1
  end

  test "keeps a named file that produced no mutants in the breakdown" do
    report = Report.from_mutants([mutant("a.ex", 1, :killed)], ["a.ex", "quiet.ex"])

    assert [{"a.ex", _judged}, {"quiet.ex", quiet}] = Report.by_file(report)
    assert quiet.mutants == []
  end
end
