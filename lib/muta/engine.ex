defmodule Muta.Engine do
  alias Muta.Config
  alias Muta.Coverage
  alias Muta.Generator
  alias Muta.Mutant
  alias Muta.Mutation
  alias Muta.Original
  alias Muta.Plan
  alias Muta.Settings
  alias Muta.Source
  alias Muta.Timing
  alias Muta.UntrustworthyError
  alias Muta.Verdict

  @patience 10
  @min_timeout_ms 200

  @spec run(Source.t(), Coverage.t(), Config.t()) :: [Mutant.t()]
  def run(%Source{} = source, coverage, %Config{} = config) do
    Settings.restored_after(fn ->
      Code.put_compiler_option(:ignore_module_conflict, true)
      ExUnit.configure(formatters: [], max_failures: 1)

      mutate(source, coverage, config)
    end)
  end

  defp mutate(%Source{} = source, coverage, %Config{} = config) do
    original = Original.compile(source)

    plans =
      source
      |> Generator.generate(config.mutators)
      |> Plan.for_mutations(source, coverage)

    vouched = vouch_for(Enum.flat_map(plans, &Plan.first_round/1), MapSet.new(), config)
    verdicts = Enum.map(plans, &try_first_round(&1, original, config))

    verdicts
    |> Enum.filter(&undecided?/1)
    |> Enum.flat_map(&Enum.concat(Plan.later_rounds(&1.plan)))
    |> vouch_for(vouched, config)

    Enum.map(verdicts, &settle(&1, original, config))
  end

  defp try_first_round(%Plan{rounds: []} = plan, _original, _config) do
    %Verdict{plan: plan, outcome: :survived, duration_ms: 0}
  end

  defp try_first_round(%Plan{} = plan, original, config) do
    judge(plan, [Plan.first_round(plan)], original, config)
  end

  defp undecided?(%Verdict{outcome: :survived} = verdict),
    do: Plan.later_rounds(verdict.plan) != []

  defp undecided?(%Verdict{}), do: false

  defp settle(%Verdict{outcome: :survived} = verdict, original, config) do
    verdict.plan |> Plan.later_rounds() |> keep_judging(verdict, original, config)
  end

  defp settle(%Verdict{} = verdict, _original, _config), do: Verdict.mutant(verdict)

  defp keep_judging([], %Verdict{} = verdict, _original, _config), do: Verdict.mutant(verdict)

  defp keep_judging(rounds, %Verdict{} = verdict, original, config) do
    verdict
    |> Verdict.followed_by(judge(verdict.plan, rounds, original, config))
    |> Verdict.mutant()
  end

  defp judge(%Plan{} = plan, rounds, %Original{} = original, %Config{} = config) do
    {duration_us, outcome} =
      :timer.tc(fn ->
        try do
          case compile_mutant(plan.mutation, original.file) do
            :compiled -> run_rounds(rounds, config)
            :invalid -> :invalid
          end
        after
          Original.restore(original)
        end
      end)

    Original.reclaim(original)

    %Verdict{plan: plan, outcome: outcome, duration_ms: div(duration_us, 1000)}
  end

  defp compile_mutant(%Mutation{} = mutation, file) do
    Code.compile_quoted(mutation.ast, file)

    :compiled
  rescue
    _a_mutation_the_compiler_rejects -> :invalid
  end

  defp run_rounds(rounds, %Config{} = config) do
    Enum.reduce_while(rounds, :survived, fn test_ids, _so_far ->
      case run_round(test_ids, config.baseline_timeout_ms) do
        :killed -> {:halt, :killed}
        :survived -> {:cont, :survived}
      end
    end)
  end

  defp run_round(test_ids, budget_ms) do
    ExUnit.configure(only_test_ids: MapSet.new(test_ids))
    task = Task.async(fn -> ExUnit.run(modules_of(test_ids)) end)

    case Task.yield(task, budget_ms) do
      {:ok, %{failures: 0}} ->
        :survived

      {:ok, %{failures: _}} ->
        :killed

      nil ->
        Task.shutdown(task, :brutal_kill)

        raise UntrustworthyError,
              "a mutant's tests did not return within #{budget_ms}ms even though ExUnit was " <>
                "given a shorter per-test timeout. Abandoning the run leaves ExUnit unable " <>
                "to start another, so the run stops here."
    end
  end

  defp vouch_for(test_ids, vouched, %Config{} = config) do
    case test_ids |> Enum.uniq() |> Enum.reject(&MapSet.member?(vouched, &1)) do
      [] ->
        vouched

      unseen ->
        Enum.each(modules_of(unseen), config.load_test_module)
        slowest_ms = ensure_baseline_is_trustworthy(unseen, config.baseline_timeout_ms)
        ExUnit.configure(timeout: max(slowest_ms * @patience, @min_timeout_ms))

        MapSet.union(vouched, MapSet.new(unseen))
    end
  end

  defp ensure_baseline_is_trustworthy(test_ids, timeout_ms) do
    {:ok, timing} = Timing.start_link()
    modules = modules_of(test_ids)

    ExUnit.configure(
      only_test_ids: MapSet.new(test_ids),
      formatters: [Timing.Formatter],
      muta_timing: timing
    )

    try do
      first = baseline(modules, timeout_ms)
      second = baseline(modules, timeout_ms)

      ensure_green(first)
      ensure_green(second)
      ensure_repeatable(first, second)

      Timing.slowest_ms(timing)
    after
      Timing.stop(timing)
      ExUnit.configure(formatters: [])
    end
  end

  defp modules_of(test_ids) do
    test_ids |> Enum.map(fn {test_module, _name} -> test_module end) |> Enum.uniq()
  end

  defp baseline(modules, timeout_ms) do
    task = Task.async(fn -> ExUnit.run(modules) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, results} ->
        results

      nil ->
        raise UntrustworthyError,
              "the tests did not finish within #{timeout_ms}ms on unmutated code, " <>
                "so no mutant could be given a fair hearing"
    end
  end

  defp ensure_green(%{failures: 0}), do: :ok

  defp ensure_green(%{failures: failures}) do
    raise UntrustworthyError,
          "#{failures} test(s) fail on unmutated code. A mutant is judged by whether it " <>
            "breaks a passing suite, so there is nothing to measure until these pass."
  end

  defp ensure_repeatable(results, results), do: :ok

  defp ensure_repeatable(first, second) do
    raise UntrustworthyError,
          "two runs of the unmutated suite disagreed (#{inspect(first)} then " <>
            "#{inspect(second)}). Every mutant is judged by re-running these tests, so a " <>
            "suite that leaks state between runs would mark mutants killed for reasons " <>
            "that have nothing to do with the mutation."
  end
end
