defmodule Muta.Engine do
  alias Muta.Config
  alias Muta.Coverage
  alias Muta.Generator
  alias Muta.Mutant
  alias Muta.Mutation
  alias Muta.Report
  alias Muta.Source
  alias Muta.Target
  alias Muta.UntrustworthyError

  @patience 10
  @min_timeout_ms 200

  @spec run(String.t(), Target.t(), Coverage.t(), Config.t()) :: Report.t()
  def run(source, %Target{} = target, coverage, %Config{} = config) do
    conflicts_allowed = Code.get_compiler_option(:ignore_module_conflict)
    formatters = ExUnit.configuration()[:formatters]
    only_test_ids = ExUnit.configuration()[:only_test_ids]
    max_failures = ExUnit.configuration()[:max_failures]
    test_timeout = ExUnit.configuration()[:timeout]
    Code.put_compiler_option(:ignore_module_conflict, true)
    ExUnit.configure(formatters: [], max_failures: 1)

    try do
      mutate(source, target, coverage, config)
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts_allowed)

      ExUnit.configure(
        formatters: formatters,
        only_test_ids: only_test_ids,
        max_failures: max_failures,
        timeout: test_timeout
      )
    end
  end

  defp mutate(source, %Target{} = target, coverage, %Config{} = config) do
    originals = Code.compile_string(source, target.file)
    modules = Enum.map(originals, fn {module, _binary} -> module end)
    functions = Source.functions_by_line(source, target.file)
    mutations = Generator.generate(source, target.file, config.mutators)

    reachable =
      mutations
      |> Enum.flat_map(&covering_tests(coverage, modules, functions, &1.line))
      |> Enum.uniq()

    timeout_ms = timeout_for(reachable, config.baseline_timeout_ms)
    ExUnit.configure(timeout: timeout_ms)

    focus = Coverage.focus(coverage, modules)
    budget = config.baseline_timeout_ms

    mutations
    |> Enum.map(&evaluate(&1, originals, modules, functions, coverage, target, focus, budget))
    |> Report.from_mutants()
  end

  defp timeout_for([], _baseline_timeout_ms), do: @min_timeout_ms

  defp timeout_for(reachable, baseline_timeout_ms) do
    baseline_ms = ensure_baseline_is_trustworthy(reachable, baseline_timeout_ms)

    max(baseline_ms * @patience, @min_timeout_ms)
  end

  defp ensure_baseline_is_trustworthy(test_ids, timeout_ms) do
    ExUnit.configure(only_test_ids: MapSet.new(test_ids))
    modules = modules_of(test_ids)

    first = baseline(modules, timeout_ms)
    {duration_us, second} = :timer.tc(fn -> baseline(modules, timeout_ms) end)

    ensure_green(first)
    ensure_green(second)
    ensure_repeatable(first, second)

    div(duration_us, 1000)
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

  defp evaluate(mutation, originals, modules, functions, coverage, target, focus, timeout) do
    case covering_tests(coverage, modules, functions, mutation.line) do
      [] -> Mutant.evaluated(mutation, :survived, 0)
      test_ids -> judge(mutation, originals, target, rounds(test_ids, focus), timeout)
    end
  end

  defp rounds(test_ids, focus) do
    test_ids
    |> Enum.group_by(fn {module, _name} -> module end)
    |> Enum.sort_by(fn {module, _ids} -> -Map.get(focus, module, 0) end)
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

  defp judge(%Mutation{} = mutation, originals, %Target{} = target, rounds, timeout_ms) do
    {duration_us, outcome} =
      :timer.tc(fn ->
        try do
          Code.compile_quoted(mutation.ast, target.file)
          verdict(rounds, timeout_ms)
        rescue
          _error -> :invalid
        after
          restore(originals, target.file)
        end
      end)

    reclaim_mutant_code(originals)
    Mutant.evaluated(mutation, outcome, div(duration_us, 1000))
  end

  defp verdict(rounds, budget_ms) do
    Enum.reduce_while(rounds, :survived, fn {modules, test_ids}, _so_far ->
      case run_round(modules, test_ids, budget_ms) do
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
