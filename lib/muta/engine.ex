defmodule Muta.Engine do
  alias Muta.Config
  alias Muta.Mutant
  alias Muta.Mutation
  alias Muta.Original
  alias Muta.Source
  alias Muta.Suite
  alias Muta.UntrustworthyError

  @spec judge(Mutation.t(), Original.t(), Suite.t(), Config.t()) :: Mutant.t()
  def judge(%Mutation{} = mutation, %Original{} = original, %Suite{} = suite, %Config{} = config) do
    outcome =
      try do
        case compile_mutant(mutation, original.source) do
          :compiled -> verdict(suite, config)
          :invalid -> :invalid
        end
      after
        Original.restore(original)
      end

    Original.reclaim(original)

    Mutant.evaluated(mutation, outcome)
  end

  defp compile_mutant(%Mutation{} = mutation, %Source{} = source) do
    {outcome, _diagnostics} = Code.with_diagnostics(fn -> load(mutation, source) end)

    outcome
  end

  defp load(%Mutation{} = mutation, %Source{} = source) do
    mutation
    |> Mutation.apply_to(source.ast)
    |> Source.compilable()
    |> Code.compile_quoted(source.file)

    :compiled
  rescue
    _exception -> :invalid
  end

  defp verdict(%Suite{} = suite, %Config{} = config) do
    case run_tests(suite, config) do
      :passed -> :survived
      :failed -> confirmed_verdict(suite, config)
    end
  end

  defp confirmed_verdict(%Suite{} = suite, %Config{} = config) do
    case run_tests(suite, config) do
      :failed -> :killed
      :passed -> :unstable
    end
  end

  defp run_tests(%Suite{} = suite, %Config{} = config) do
    task = Task.async(fn -> ExUnit.run(suite.modules) end)

    case Task.yield(task, config.baseline_timeout_ms) do
      {:ok, %{failures: 0}} ->
        :passed

      {:ok, %{failures: _failures}} ->
        :failed

      nil ->
        Task.shutdown(task, :brutal_kill)

        raise UntrustworthyError,
              "a mutant's tests did not return within #{config.baseline_timeout_ms}ms. This is the configured " <>
                "overall timeout for one mutant test attempt; the mutation has no verdict."
    end
  end
end
