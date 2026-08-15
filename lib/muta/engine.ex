defmodule Muta.Engine do
  alias Muta.Config
  alias Muta.Coverage
  alias Muta.Generator
  alias Muta.Mutant
  alias Muta.Mutation
  alias Muta.Settings
  alias Muta.Source
  alias Muta.Timing
  alias Muta.UntrustworthyError

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
    originals = Code.compile_string(source.code, source.file)
    modules = Enum.map(originals, fn {module, _binary} -> module end)
    focus = Coverage.focus(coverage, modules)

    plans =
      source
      |> Generator.generate(config.mutators)
      |> Enum.map(fn mutation ->
        test_ids = covering_tests(coverage, modules, source.functions_by_line, mutation.line)

        {mutation, rounds(test_ids, focus)}
      end)

    vouched = vouch_for(ids_from(plans, &Enum.take(&1, 1)), MapSet.new(), config)

    first = Enum.map(plans, &judge_round(&1, 1, originals, source, config))

    pending = first |> Enum.filter(&undecided?/1) |> Enum.map(&elem(&1, 0))
    vouch_for(ids_from(pending, &Enum.drop(&1, 1)), vouched, config)

    Enum.map(first, &settle(&1, originals, source, config))
  end

  defp ids_from(plans, which_rounds) do
    for {_mutation, rounds} <- plans,
        {_modules, test_ids} <- which_rounds.(rounds),
        test_id <- test_ids,
        uniq: true,
        do: test_id
  end

  defp judge_round({mutation, rounds} = plan, round, originals, source, config) do
    case Enum.at(rounds, round - 1) do
      nil -> {plan, :survived, 0}
      _round -> {plan, judge(mutation, [Enum.at(rounds, round - 1)], originals, source, config)}
    end
  end

  defp undecided?({{_mutation, rounds}, {:survived, _ms}}), do: length(rounds) > 1
  defp undecided?(_judged), do: false

  defp settle({{mutation, _rounds}, :survived, 0}, _originals, _source, _config) do
    Mutant.evaluated(mutation, :survived, 0)
  end

  defp settle({{mutation, rounds}, {:survived, ms}}, originals, source, config)
       when length(rounds) > 1 do
    {outcome, more_ms} =
      judge(mutation, Enum.drop(rounds, 1), originals, source, config)

    Mutant.evaluated(mutation, outcome, ms + more_ms)
  end

  defp settle({{mutation, _rounds}, {outcome, ms}}, _originals, _source, _config) do
    Mutant.evaluated(mutation, outcome, ms)
  end

  defp vouch_for(test_ids, vouched, %Config{} = config) do
    case Enum.reject(test_ids, &MapSet.member?(vouched, &1)) do
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
    test_ids |> Enum.map(fn {module, _name} -> module end) |> Enum.uniq()
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

  defp rounds(test_ids, focus) do
    test_ids
    |> Enum.group_by(fn {module, _name} -> module end)
    |> Enum.sort_by(fn {module, ids} -> {-Map.get(focus, module, 0), length(ids)} end)
    |> split_off_closest()
  end

  defp split_off_closest([]), do: []
  defp split_off_closest([{module, test_ids}]), do: [{[module], test_ids}]

  defp split_off_closest([{module, test_ids} | rest]) do
    [
      {[module], test_ids},
      {Enum.map(rest, &elem(&1, 0)), Enum.flat_map(rest, &elem(&1, 1))}
    ]
  end

  defp covering_tests(coverage, modules, functions, line) do
    case Map.fetch(functions, line) do
      {:ok, signature} -> Coverage.tests_covering(coverage, modules, signature)
      :error -> []
    end
  end

  defp judge(%Mutation{} = mutation, rounds, originals, %Source{} = source, config) do
    {duration_us, outcome} =
      :timer.tc(fn ->
        try do
          case compile_mutant(mutation, source.file) do
            :compiled -> verdict(rounds, config)
            :invalid -> :invalid
          end
        after
          restore(originals, source.file)
        end
      end)

    reclaim_mutant_code(originals)

    {outcome, div(duration_us, 1000)}
  end

  defp compile_mutant(%Mutation{} = mutation, file) do
    Code.compile_quoted(mutation.ast, file)

    :compiled
  rescue
    _a_mutation_the_compiler_rejects -> :invalid
  end

  defp verdict(rounds, %Config{} = config) do
    Enum.reduce_while(rounds, :survived, fn {modules, test_ids}, _so_far ->
      case run_round(modules, test_ids, config.baseline_timeout_ms) do
        :killed -> {:halt, :killed}
        :survived -> {:cont, :survived}
      end
    end)
  end

  defp run_round(modules, test_ids, budget_ms) do
    ExUnit.configure(only_test_ids: MapSet.new(test_ids))
    task = Task.async(fn -> ExUnit.run(modules) end)

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

  defp restore(originals, file) do
    path = String.to_charlist(file)

    Enum.each(originals, fn {module, binary} -> :code.load_binary(module, path, binary) end)
  end

  defp reclaim_mutant_code(originals) do
    Enum.each(originals, fn {module, _binary} -> ensure_no_process_still_runs_mutant(module) end)
  end

  defp ensure_no_process_still_runs_mutant(module) do
    if :code.soft_purge(module) do
      :ok
    else
      raise UntrustworthyError,
            "a process is still running mutated #{inspect(module)} code after its test " <>
              "finished. The next mutant would be judged partly against this one, so the " <>
              "run stops here rather than reporting a verdict shaped by it."
    end
  end
end
