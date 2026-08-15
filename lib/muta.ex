defmodule Muta do
  alias Muta.Config
  alias Muta.Engine
  alias Muta.Report
  alias Muta.Target

  @spec run(Config.t()) :: Report.t()
  def run(%Config{} = config) do
    config.targets
    |> Enum.flat_map(&mutants_for(&1, config))
    |> Report.from_mutants()
  end

  defp mutants_for(%Target{} = target, %Config{} = config) do
    source = File.read!(target.file)

    report =
      Engine.run(source, target.file, target.test_modules, config.mutators,
        timeout_ms: config.timeout_ms
      )

    report.mutants
  end
end
