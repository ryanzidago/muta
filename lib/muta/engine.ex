defmodule Muta.Engine do
  alias Muta.Generator
  alias Muta.Mutant
  alias Muta.Mutation
  alias Muta.Report
  alias Muta.UntrustworthyError

  @default_baseline_timeout_ms 30_000
  @patience 10
  @min_timeout_ms 200

  @spec run(String.t(), Path.t(), [module()], [module()], keyword()) :: Report.t()
  def run(source, file, test_modules, mutators, opts \\ []) do
    baseline_timeout_ms =
      Keyword.get(opts, :baseline_timeout_ms, @default_baseline_timeout_ms)

    conflicts_allowed = Code.get_compiler_option(:ignore_module_conflict)
    formatters = ExUnit.configuration()[:formatters]
    only_test_ids = ExUnit.configuration()[:only_test_ids]
    Code.put_compiler_option(:ignore_module_conflict, true)
    ExUnit.configure(formatters: [], only_test_ids: test_ids(test_modules))

    try do
      originals = Code.compile_string(source, file)
      baseline_ms = ensure_baseline_is_trustworthy(test_modules, baseline_timeout_ms)
      timeout_ms = max(baseline_ms * @patience, @min_timeout_ms)

      source
      |> Generator.generate(file, mutators)
      |> Enum.map(&evaluate(&1, originals, file, test_modules, timeout_ms))
      |> Report.from_mutants()
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts_allowed)
      ExUnit.configure(formatters: formatters, only_test_ids: only_test_ids)
    end
  end

  defp test_ids(test_modules) do
    test_modules
    |> Enum.flat_map(fn module -> module.__ex_unit__().tests end)
    |> MapSet.new(fn test -> {test.module, test.name} end)
  end

  defp ensure_baseline_is_trustworthy(test_modules, timeout_ms) do
    first = baseline(test_modules, timeout_ms)
    {duration_us, second} = :timer.tc(fn -> baseline(test_modules, timeout_ms) end)

    ensure_green(first)
    ensure_green(second)
    ensure_repeatable(first, second)

    div(duration_us, 1000)
  end

  defp baseline(test_modules, timeout_ms) do
    task = Task.async(fn -> ExUnit.run(test_modules) end)

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

  defp evaluate(%Mutation{} = mutation, originals, file, test_modules, timeout_ms) do
    {duration_us, outcome} =
      :timer.tc(fn ->
        try do
          Code.compile_quoted(mutation.ast, file)
          verdict(test_modules, timeout_ms)
        rescue
          _error -> :invalid
        after
          restore(originals, file)
        end
      end)

    reclaim_mutant_code(originals, outcome)
    Mutant.evaluated(mutation, outcome, div(duration_us, 1000))
  end

  defp verdict(test_modules, timeout_ms) do
    task = Task.async(fn -> ExUnit.run(test_modules) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, %{failures: 0}} -> :survived
      {:ok, %{failures: _}} -> :killed
      nil -> :timed_out
    end
  end

  defp restore(originals, file) do
    path = String.to_charlist(file)

    Enum.each(originals, fn {module, binary} -> :code.load_binary(module, path, binary) end)
  end

  defp reclaim_mutant_code(originals, :timed_out) do
    Enum.each(originals, fn {module, _binary} -> :code.purge(module) end)
  end

  defp reclaim_mutant_code(originals, _ran_to_completion) do
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
