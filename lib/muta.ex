defmodule Muta do
  alias Muta.Config
  alias Muta.Coverage
  alias Muta.Engine
  alias Muta.Report
  alias Muta.Source

  @spec coverage(Config.t()) :: Coverage.t()
  def coverage(%Config{} = config) do
    Coverage.build(Config.target_modules(config), config.test_modules)
  end

  @spec unknown_functions(Config.t(), Coverage.t()) :: [{module(), Source.signature()}]
  def unknown_functions(%Config{} = config, coverage) do
    for source <- config.sources,
        module <- source.modules,
        signature <- Source.signatures(source),
        not Map.has_key?(coverage, {module, signature}),
        uniq: true,
        do: {module, signature}
  end

  @spec run(Config.t()) :: Report.t()
  def run(%Config{} = config), do: run(config, coverage(config))

  @spec run(Config.t(), Coverage.t()) :: Report.t()
  def run(%Config{} = config, coverage) do
    config.sources
    |> Enum.flat_map(&Engine.run(&1, coverage, config))
    |> Report.from_mutants()
  end
end
