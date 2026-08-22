defmodule Muta.Baseline do
  alias Muta.Config
  alias Muta.Suite
  alias Muta.UntrustworthyError

  @spec ensure_trustworthy(Suite.t(), Config.t()) :: :ok
  def ensure_trustworthy(%Suite{} = suite, %Config{} = config) do
    first = run(suite, config)
    second = run(suite, config)

    ensure_green(first)
    ensure_repeatable(first, second)
  end

  defp run(%Suite{} = suite, %Config{} = config) do
    task = Task.async(fn -> ExUnit.run(suite.modules) end)

    case Task.yield(task, config.baseline_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, results} ->
        results

      nil ->
        raise UntrustworthyError,
              "the tests did not finish within #{config.baseline_timeout_ms}ms on unmutated " <>
                "code, so no mutant could be given a fair hearing"
    end
  end

  defp ensure_green(%{failures: 0, total: total, skipped: skipped, excluded: excluded})
       when total - skipped - excluded > 0,
       do: :ok

  defp ensure_green(%{failures: 0}) do
    raise UntrustworthyError,
          "the tests you named ran nothing. Every test in them is skipped or excluded by a " <>
            "tag, so a passing run says only that nothing happened, and every mutant would " <>
            "be reported as surviving."
  end

  defp ensure_green(%{failures: failures}) do
    raise UntrustworthyError,
          "#{failures} test(s) fail on unmutated code. A mutant is judged by whether it " <>
            "breaks a passing suite, so there is nothing to measure until these pass."
  end

  defp ensure_repeatable(results, results), do: :ok

  defp ensure_repeatable(first, second) do
    raise UntrustworthyError,
          "two runs of the unmutated tests disagreed (#{inspect(first)} then " <>
            "#{inspect(second)}). Every mutant is judged by re-running these tests, so a " <>
            "suite that leaks state between runs would mark mutants killed for reasons " <>
            "that have nothing to do with the mutation."
  end
end
