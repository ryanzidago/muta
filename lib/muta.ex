defmodule Muta do
  alias Muta.Config
  alias Muta.Coverage
  alias Muta.Engine
  alias Muta.Report
  alias Muta.Source
  alias Muta.Target

  @spec coverage(Config.t()) :: Coverage.t()
  def coverage(%Config{} = config) do
    Coverage.build(modules_under_test(config), config.test_modules)
  end

  @spec modules_under_test(Config.t()) :: [module()]
  def modules_under_test(%Config{} = config) do
    Enum.flat_map(config.targets, fn %Target{} = target ->
      target.file |> File.read!() |> Source.modules(target.file)
    end)
  end

  @spec unknown_functions(Config.t(), Coverage.t()) :: [{module(), Source.signature()}]
  def unknown_functions(%Config{} = config, coverage) do
    for %Target{} = target <- config.targets,
        source = File.read!(target.file),
        module <- Source.modules(source, target.file),
        signature <- signatures(source, target.file),
        not Map.has_key?(coverage, {module, signature}),
        uniq: true,
        do: {module, signature}
  end

  defp signatures(source, file) do
    source |> Source.functions_by_line(file) |> Map.values() |> Enum.uniq()
  end

  @spec run(Config.t()) :: Report.t()
  def run(%Config{} = config), do: run(config, coverage(config))

  @spec run(Config.t(), Coverage.t()) :: Report.t()
  def run(%Config{} = config, coverage) do
    config.targets
    |> Enum.flat_map(fn %Target{} = target ->
      source = File.read!(target.file)
      report = Engine.run(source, target, coverage, config)
      report.mutants
    end)
    |> Report.from_mutants()
  end
end
