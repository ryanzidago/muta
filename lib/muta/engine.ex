defmodule Muta.Engine do
  alias Muta.Config
  alias Muta.Generator
  alias Muta.Mutant
  alias Muta.Mutation
  alias Muta.Original
  alias Muta.Source
  alias Muta.UntrustworthyError

  @spec run(Source.t(), Config.t()) :: [Mutant.t()]
  def run(%Source{} = source, %Config{} = config) do
    original = Original.compile(source)

    source
    |> Generator.generate(config.mutators)
    |> Enum.map(&judge(&1, original, config))
  end

  defp judge(%Mutation{} = mutation, %Original{} = original, %Config{} = config) do
    {duration_us, outcome} =
      :timer.tc(fn ->
        try do
          case compile_mutant(mutation, original.file) do
            :compiled -> verdict(config)
            :invalid -> :invalid
          end
        after
          Original.restore(original)
        end
      end)

    Original.reclaim(original)

    Mutant.evaluated(mutation, outcome, div(duration_us, 1000))
  end

  defp compile_mutant(%Mutation{} = mutation, file) do
    Code.compile_quoted(mutation.ast, file)

    :compiled
  rescue
    _a_mutation_the_compiler_rejects -> :invalid
  end

  defp verdict(%Config{} = config) do
    task = Task.async(fn -> ExUnit.run(config.test_modules) end)

    case Task.yield(task, config.baseline_timeout_ms) do
      {:ok, %{failures: 0}} ->
        :survived

      {:ok, %{failures: _}} ->
        :killed

      nil ->
        Task.shutdown(task, :brutal_kill)

        raise UntrustworthyError,
              "a mutant's tests did not return within #{config.baseline_timeout_ms}ms even " <>
                "though ExUnit was given a shorter per-test timeout. Abandoning the run " <>
                "leaves ExUnit unable to start another, so the run stops here."
    end
  end
end
