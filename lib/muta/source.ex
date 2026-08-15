defmodule Muta.Source do
  @type signature :: {atom(), arity()}

  @spec modules(String.t(), Path.t()) :: [module()]
  def modules(source, file) do
    {_ast, found} =
      source
      |> Code.string_to_quoted!(file: file)
      |> Macro.prewalk([], fn
        {:defmodule, _meta, [{:__aliases__, _alias_meta, parts} | _rest]} = node, found ->
          {node, [Module.concat(parts) | found]}

        node, found ->
          {node, found}
      end)

    Enum.reverse(found)
  end

  @spec functions_by_line(String.t(), Path.t()) :: %{pos_integer() => signature()}
  def functions_by_line(source, file) do
    source
    |> Code.string_to_quoted!(file: file)
    |> clauses()
    |> Enum.flat_map(fn {signature, span} -> Enum.map(span, &{&1, signature}) end)
    |> Map.new()
  end

  defp clauses(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [head | _rest]} = node, found when kind in [:def, :defp] ->
          {node, [{signature(head), Keyword.fetch!(meta, :line)..last_line(node)} | found]}

        node, found ->
          {node, found}
      end)

    found
  end

  defp signature({:when, _meta, [head | _guards]}), do: signature(head)
  defp signature({name, _meta, args}) when is_list(args), do: {name, length(args)}
  defp signature({name, _meta, _no_args}), do: {name, 0}

  defp last_line(ast) do
    {_ast, line} =
      Macro.prewalk(ast, 0, fn
        {_form, meta, _args} = node, highest ->
          {node, max(highest, Keyword.get(meta, :line, 0))}

        node, highest ->
          {node, highest}
      end)

    line
  end
end
