defmodule Muta do
  alias Muta.Acceptance
  alias Muta.Baseline
  alias Muta.Config
  alias Muta.Fleet
  alias Muta.Generator
  alias Muta.Mutation
  alias Muta.Report
  alias Muta.Settings
  alias Muta.Suite
  alias Muta.UntrustworthyError

  @spec run(Config.t()) :: Report.t()
  def run(%Config{} = config) do
    Settings.restored_after(fn ->
      Code.put_compiler_option(:ignore_module_conflict, true)
      Code.require_file(config.test_helper)
      suite = Suite.load(config.test_files)
      ExUnit.configure(formatters: [], max_failures: 1, only_test_ids: suite.test_ids)

      Baseline.ensure_trustworthy(suite, config)

      {generated, in_type_guards} =
        config.sources
        |> Enum.map(&Generator.generate(&1, config.mutators))
        |> Enum.unzip()

      {judged, skipped} =
        generated
        |> List.flatten()
        |> Enum.split_with(&on_a_named_line?(&1, config.lines))

      {judged, failures, pending} = Fleet.judge(judged, config)
      judged = Acceptance.apply_to(config.acceptances, judged)

      report =
        judged
        |> Report.from_mutants(
          Enum.map(config.sources, & &1.file),
          length(skipped),
          Enum.sum(in_type_guards)
        )

      if failures == [] and pending == [] do
        report
      else
        %{
          report
          | complete?: false,
            failures: failures,
            pending: pending,
            score: nil
        }
      end
      |> ensure_something_was_scored()
    end)
  end

  defp on_a_named_line?(%Mutation{} = mutation, lines) do
    MapSet.member?(Map.fetch!(lines, mutation.file), mutation.line)
  end

  defp ensure_something_was_scored(%Report{complete?: false} = report), do: report

  defp ensure_something_was_scored(%Report{killed: 0, survived: 0} = report)
       when report.invalid > 0 or report.unstable > 0 do
    raise UntrustworthyError,
          "not one of these #{length(report.mutants)} mutant(s) produced a verdict " <>
            "(#{report.invalid} rejected by the compiler, #{report.unstable} judged by a " <>
            "test that would not give the same answer twice). Scoring that as a percentage " <>
            "would read as a pass."
  end

  defp ensure_something_was_scored(%Report{} = report), do: report
end
