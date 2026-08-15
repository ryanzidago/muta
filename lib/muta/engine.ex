defmodule Muta.Engine do
  alias Muta.Generator
  alias Muta.Mutant
  alias Muta.Mutation
  alias Muta.Report

  @default_timeout_ms 5_000

  @spec run(String.t(), Path.t(), [module()], [module()], keyword()) :: Report.t()
  def run(source, file, test_modules, mutators, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    conflicts_allowed = Code.get_compiler_option(:ignore_module_conflict)
    formatters = ExUnit.configuration()[:formatters]
    Code.put_compiler_option(:ignore_module_conflict, true)
    ExUnit.configure(formatters: [])

    try do
      originals = compile(source, file)

      source
      |> Generator.generate(file, mutators)
      |> Enum.map(&evaluate(&1, originals, file, test_modules, timeout_ms))
      |> Report.from_mutants()
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts_allowed)
      ExUnit.configure(formatters: formatters)
    end
  end

  defp compile(source, file), do: Code.compile_string(source, file)

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

    Mutant.evaluated(mutation, outcome, div(duration_us, 1000))
  end

  # The verdict is read from ExUnit's own result rather than its printed output,
  # so a change to the formatter can never be mistaken for a passing suite.
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
end
