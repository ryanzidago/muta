defmodule Muta.Coverage do
  alias Muta.Source

  @enforce_keys [:by_function, :by_module]
  defstruct [:by_function, :by_module]

  @type test_id :: {module(), atom()}

  @type t :: %__MODULE__{
          by_function: %{{module(), Source.signature()} => [test_id()]},
          by_module: %{module() => [test_id()]}
        }

  @spec empty() :: t()
  def empty, do: %__MODULE__{by_function: %{}, by_module: %{}}

  @spec build([module()], [module()]) :: t()
  def build(target_modules, test_modules) do
    only_test_ids = ExUnit.configuration()[:only_test_ids]
    formatters = ExUnit.configuration()[:formatters]
    ExUnit.configure(formatters: [])

    try do
      instrumented(target_modules, fn ->
        test_modules
        |> Enum.flat_map(&test_ids_in/1)
        |> Enum.reduce(empty(), &record_hits(&1, &2, target_modules))
      end)
    after
      ExUnit.configure(formatters: formatters, only_test_ids: only_test_ids)
    end
  end

  @spec tests_covering(t(), [module()], Source.signature()) :: [test_id()]
  def tests_covering(%__MODULE__{} = coverage, modules, signature) do
    modules
    |> Enum.flat_map(&tests_for(coverage, &1, signature))
    |> Enum.uniq()
  end

  @spec knows?(t(), module(), Source.signature()) :: boolean()
  def knows?(%__MODULE__{} = coverage, module, signature) do
    Map.has_key?(coverage.by_function, {module, signature})
  end

  @spec settle(t(), [{module(), Source.signature()}], [module()]) :: t()
  def settle(%__MODULE__{} = coverage, unknown, test_modules) do
    target_modules = unknown |> Enum.map(fn {module, _signature} -> module end) |> Enum.uniq()
    touched = touched_signatures(target_modules, test_modules)

    Enum.reduce(unknown, coverage, fn key, settled ->
      if MapSet.member?(touched, key), do: settled, else: put_in(settled.by_function[key], [])
    end)
  end

  @spec focus(t(), [module()]) :: %{module() => pos_integer()}
  def focus(%__MODULE__{} = coverage, modules) do
    wanted = MapSet.new(modules)

    signatures_seen =
      for {{module, signature}, test_ids} <- coverage.by_function,
          MapSet.member?(wanted, module),
          {test_module, _name} <- test_ids,
          reduce: %{} do
        seen -> Map.update(seen, test_module, MapSet.new([signature]), &MapSet.put(&1, signature))
      end

    Map.new(signatures_seen, fn {test_module, signatures} ->
      {test_module, MapSet.size(signatures)}
    end)
  end

  @spec test_modules_reaching(t(), [module()]) :: [module()]
  def test_modules_reaching(%__MODULE__{} = coverage, modules) do
    for module <- modules,
        {test_module, _name} <- Map.get(coverage.by_module, module, []),
        uniq: true,
        do: test_module
  end

  defp tests_for(coverage, module, signature) do
    case Map.fetch(coverage.by_function, {module, signature}) do
      {:ok, test_ids} -> test_ids
      :error -> Map.get(coverage.by_module, module, [])
    end
  end

  defp touched_signatures(target_modules, test_modules) do
    only_test_ids = ExUnit.configuration()[:only_test_ids]
    formatters = ExUnit.configuration()[:formatters]
    ExUnit.configure(formatters: [], only_test_ids: nil)

    try do
      instrumented(target_modules, fn ->
        :cover.reset()
        ExUnit.run(test_modules)

        for target <- target_modules, signature <- functions_called(target), into: MapSet.new() do
          {target, signature}
        end
      end)
    after
      ExUnit.configure(formatters: formatters, only_test_ids: only_test_ids)
    end
  end

  defp instrumented(target_modules, judge) do
    :cover.start()
    Enum.each(target_modules, &instrument/1)

    try do
      judge.()
    after
      :cover.stop()
      Enum.each(target_modules, &reload/1)
    end
  end

  defp instrument(module) do
    case :cover.compile_beam(module) do
      {:ok, ^module} ->
        :ok

      {:error, {:no_abstract_code, beam}} ->
        raise Muta.UntrustworthyError,
              "#{inspect(module)} was compiled without debug info (#{beam}), so there is no " <>
                "way to tell which tests reach it. Every mutant would look like a survivor."

      {:error, reason} ->
        raise Muta.UntrustworthyError,
              "#{inspect(module)} could not be instrumented for coverage " <>
                "(#{inspect(reason)}), so which tests reach it is unknown."
    end
  end

  defp test_ids_in(test_module) do
    Enum.map(test_module.__ex_unit__().tests, fn test -> {test.module, test.name} end)
  end

  defp record_hits({test_module, _name} = test_id, coverage, target_modules) do
    :cover.reset()
    ExUnit.configure(only_test_ids: MapSet.new([test_id]))
    ExUnit.run([test_module])

    Enum.reduce(target_modules, coverage, fn target, recorded ->
      case functions_called(target) do
        [] -> recorded
        signatures -> record(recorded, target, signatures, test_id)
      end
    end)
  end

  defp record(coverage, target, signatures, test_id) do
    %__MODULE__{
      by_function: Enum.reduce(signatures, coverage.by_function, &add(&2, {target, &1}, test_id)),
      by_module: add(coverage.by_module, target, test_id)
    }
  end

  defp functions_called(module) do
    case :cover.analyse(module, :calls, :function) do
      {:ok, results} ->
        for {{_module, name, arity}, calls} <- results, calls > 0, do: {name, arity}

      {:error, _reason} ->
        []
    end
  end

  defp add(index, key, test_id) do
    Map.update(index, key, [test_id], fn test_ids -> [test_id | test_ids] end)
  end

  defp reload(module) do
    :code.purge(module)
    :code.load_file(module)
  end
end
