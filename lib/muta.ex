defmodule Muta do
  alias Muta.Baseline
  alias Muta.Config
  alias Muta.Engine
  alias Muta.Report
  alias Muta.Settings

  @patience 10
  @min_timeout_ms 200

  @spec run(Config.t()) :: Report.t()
  def run(%Config{} = config) do
    Settings.restored_after(fn ->
      Code.put_compiler_option(:ignore_module_conflict, true)
      ExUnit.configure(formatters: [], max_failures: 1, only_test_ids: test_ids(config))
      ExUnit.configure(timeout: per_test_timeout(config))

      config.sources
      |> Enum.flat_map(&Engine.run(&1, config))
      |> Report.from_mutants()
    end)
  end

  defp per_test_timeout(%Config{} = config) do
    max(Baseline.slowest_test_ms(config) * @patience, @min_timeout_ms)
  end

  defp test_ids(%Config{} = config) do
    for module <- config.test_modules,
        test <- module.__ex_unit__().tests,
        into: MapSet.new(),
        do: {test.module, test.name}
  end
end
