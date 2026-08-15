defmodule Muta.Coverage do
  alias Muta.Source

  @type test_id :: {module(), atom()}
  @type t :: %{{module(), Source.signature()} => [test_id()]}

  @spec build([module()], [module()]) :: t()
  def build(target_modules, test_modules) do
    only_test_ids = ExUnit.configuration()[:only_test_ids]
    formatters = ExUnit.configuration()[:formatters]
    ExUnit.configure(formatters: [])

    :cover.start()
    Enum.each(target_modules, &instrument/1)

    try do
      test_modules
      |> Enum.flat_map(&test_ids_in/1)
      |> Enum.reduce(%{}, &record_hits(&1, &2, target_modules))
    after
      :cover.stop()
      Enum.each(target_modules, &reload/1)
      ExUnit.configure(formatters: formatters, only_test_ids: only_test_ids)
    end
  end

  @spec tests_covering(t(), [module()], Source.signature()) :: [test_id()]
  def tests_covering(coverage, modules, signature) do
    modules
    |> Enum.flat_map(&tests_for(coverage, &1, signature))
    |> Enum.uniq()
  end

  @spec note_unreached(t(), [module()], [module()], [{module(), Source.signature()}]) :: t()
  def note_unreached(coverage, target_modules, test_modules, unknown) do
    touched = touched_signatures(target_modules, test_modules)

    Enum.reduce(unknown, coverage, fn key, acc ->
      if MapSet.member?(touched, key), do: acc, else: Map.put(acc, key, [])
    end)
  end

  defp touched_signatures(target_modules, test_modules) do
    only_test_ids = ExUnit.configuration()[:only_test_ids]
    formatters = ExUnit.configuration()[:formatters]
    ExUnit.configure(formatters: [], only_test_ids: nil)

    :cover.start()
    Enum.each(target_modules, &instrument/1)

    try do
      :cover.reset()
      ExUnit.run(test_modules)

      for target <- target_modules, signature <- functions_called(target), into: MapSet.new() do
        {target, signature}
      end
    after
      :cover.stop()
      Enum.each(target_modules, &reload/1)
      ExUnit.configure(formatters: formatters, only_test_ids: only_test_ids)
    end
  end

  @spec focus(t(), [module()]) :: %{module() => pos_integer()}
  def focus(coverage, modules) do
    wanted = MapSet.new(modules)

    reached =
      for {{module, signature}, test_ids} <- coverage,
          signature != :any_function,
          MapSet.member?(wanted, module),
          {test_module, _name} <- test_ids,
          reduce: %{} do
        seen -> Map.update(seen, test_module, MapSet.new([signature]), &MapSet.put(&1, signature))
      end

    Map.new(reached, fn {test_module, signatures} ->
      {test_module, MapSet.size(signatures)}
    end)
  end

  @spec test_modules_reaching(t(), [module()]) :: [module()]
  def test_modules_reaching(coverage, modules) do
    wanted = MapSet.new(modules)

    for {{module, _signature}, test_ids} <- coverage,
        MapSet.member?(wanted, module),
        {test_module, _name} <- test_ids,
        uniq: true,
        do: test_module
  end

  defp tests_for(coverage, module, signature) do
    case Map.fetch(coverage, {module, signature}) do
      {:ok, test_ids} -> test_ids
      :error -> Map.get(coverage, {module, :any_function}, [])
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

    Enum.reduce(target_modules, coverage, fn target, acc ->
      case functions_called(target) do
        [] ->
          acc

        signatures ->
          signatures
          |> Enum.reduce(acc, &add(&2, {target, &1}, test_id))
          |> add({target, :any_function}, test_id)
      end
    end)
  end

  defp functions_called(module) do
    case :cover.analyse(module, :calls, :function) do
      {:ok, results} ->
        for {{_module, name, arity}, calls} <- results, calls > 0, do: {name, arity}

      {:error, _reason} ->
        []
    end
  end

  defp add(coverage, key, test_id) do
    Map.update(coverage, key, [test_id], fn ids -> [test_id | ids] end)
  end

  defp reload(module) do
    :code.purge(module)
    :code.load_file(module)
  end
end
