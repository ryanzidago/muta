defmodule Muta do
  alias Muta.Baseline
  alias Muta.Config
  alias Muta.Engine
  alias Muta.Report
  alias Muta.Settings
  alias Muta.UntrustworthyError

  @patience 10
  @min_timeout_ms 200

  @spec run(Config.t()) :: Report.t()
  def run(%Config{} = config) do
    Settings.restored_after(fn ->
      Code.put_compiler_option(:ignore_module_conflict, true)
      ExUnit.configure(formatters: [], max_failures: 1, only_test_ids: judging_tests(config))

      timeout = max(Baseline.slowest_test_ms(config) * @patience, @min_timeout_ms)
      ExUnit.configure(timeout: timeout)

      config.sources
      |> Enum.flat_map(&Engine.run(&1, config))
      |> Report.from_mutants()
      |> ensure_something_was_scored()
    end)
  end

  defp judging_tests(%Config{} = config) do
    config.test_modules
    |> Enum.flat_map(& &1.__ex_unit__().tests)
    |> Enum.map(&{&1.module, &1.name})
    |> ensure_something_to_judge_by()
  end

  defp ensure_something_to_judge_by([]) do
    raise UntrustworthyError,
          "no tests were given to judge these mutants by. Every mutant would be reported " <>
            "as surviving without a single test having run, which reads exactly like a " <>
            "codebase with no tests at all."
  end

  defp ensure_something_to_judge_by(test_ids), do: MapSet.new(test_ids)

  defp ensure_something_was_scored(%Report{killed: 0, survived: 0, invalid: invalid})
       when invalid > 0 do
    raise UntrustworthyError,
          "all #{invalid} mutant(s) were rejected by the compiler, so not one of them was " <>
            "ever run against a test. Scoring that as a percentage would read as a pass."
  end

  defp ensure_something_was_scored(%Report{} = report), do: report
end
