defmodule Muta.Source do
  @enforce_keys [:file, :code, :ast, :modules, :functions_by_line]
  defstruct [:file, :code, :ast, :modules, :functions_by_line]

  @type signature :: {atom(), arity()}

  @type t :: %__MODULE__{
          file: Path.t(),
          code: String.t(),
          ast: Macro.t(),
          modules: [module()],
          functions_by_line: %{pos_integer() => signature()}
        }

  @spec read(Path.t()) :: t()
  def read(file), do: file |> File.read!() |> parse(file)

  @spec parse(String.t(), Path.t()) :: t()
  def parse(code, file) do
    ast = Code.string_to_quoted!(code, file: file)

    %__MODULE__{
      file: file,
      code: code,
      ast: ast,
      modules: modules(ast),
      functions_by_line: functions_by_line(ast)
    }
  end

  @spec signatures(t()) :: [signature()]
  def signatures(%__MODULE__{} = source) do
    source.functions_by_line |> Map.values() |> Enum.uniq()
  end

  defp modules(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [{:__aliases__, _alias_meta, parts} | _rest]} = node, found ->
          {node, [Module.concat(parts) | found]}

        node, found ->
          {node, found}
      end)

    Enum.reverse(found)
  end

  defp functions_by_line(ast) do
    ast
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
