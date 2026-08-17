defmodule Muta.Baseline do
  alias Muta.Config
  alias Muta.Timing
  alias Muta.UntrustworthyError

  @spec slowest_test_ms(Config.t()) :: non_neg_integer()
  def slowest_test_ms(%Config{} = config) do
    {:ok, timing} = Timing.start_link()
    ExUnit.configure(formatters: [Timing.Formatter], muta_timing: timing)

    try do
      first = run(config)
      second = run(config)

      ensure_green(first)
      ensure_green(second)
      ensure_repeatable(first, second)

      Timing.slowest_ms(timing)
    after
      Timing.stop(timing)
      ExUnit.configure(formatters: [])
    end
  end

  defp run(%Config{} = config) do
    task = Task.async(fn -> ExUnit.run(config.test_modules) end)

    case Task.yield(task, config.baseline_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, results} ->
        results

      nil ->
        raise UntrustworthyError,
              "the tests did not finish within #{config.baseline_timeout_ms}ms on unmutated " <>
                "code, so no mutant could be given a fair hearing"
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
          "two runs of the unmutated tests disagreed (#{inspect(first)} then " <>
            "#{inspect(second)}). Every mutant is judged by re-running these tests, so a " <>
            "suite that leaks state between runs would mark mutants killed for reasons " <>
            "that have nothing to do with the mutation."
  end
end
