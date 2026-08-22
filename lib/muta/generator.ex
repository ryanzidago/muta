defmodule Muta.Generator do
  alias Muta.Mutation
  alias Muta.Source

  @annotations [
    :behaviour,
    :callback,
    :deprecated,
    :doc,
    :impl,
    :macrocallback,
    :moduledoc,
    :opaque,
    :spec,
    :type,
    :typedoc,
    :typep
  ]

  @spec generate(Source.t(), [module()]) :: [Mutation.t()]
  def generate(%Source{} = source, mutators) do
    source.ast
    |> candidates(mutators)
    |> Enum.map(&build(&1, source))
  end

  defp candidates(ast, mutators) do
    {_ast, {_index, found, _inside}} =
      Macro.traverse(
        ast,
        {0, [], 0},
        fn node, {index, found, inside} ->
          inside = inside + annotation(node)

          {node, {index + 1, offers(node, index, mutators, inside) ++ found, inside}}
        end,
        fn node, {index, found, inside} ->
          {node, {index, found, inside - annotation(node)}}
        end
      )

    Enum.reverse(found)
  end

  defp offers(_node, _index, _mutators, inside) when inside > 0, do: []

  defp offers(node, index, mutators, 0) do
    mutators
    |> Enum.flat_map(fn mutator ->
      Enum.map(mutator.mutations(node), &{index, line_of(node), mutator, node, &1})
    end)
    |> Enum.reverse()
  end

  defp annotation({:@, _meta, [{name, _name_meta, _args}]}) when name in @annotations, do: 1
  defp annotation(_node), do: 0

  defp build({index, line, mutator, node, replacement}, %Source{} = source) do
    %Mutation{
      file: source.file,
      line: line,
      mutator: mutator,
      original: rendered(node),
      mutated: rendered(replacement),
      at: index,
      replacement: replacement
    }
  end

  defp rendered(node), do: node |> Source.compilable() |> Macro.to_string()

  defp line_of(node), do: node |> lines_in() |> Enum.min()

  defp lines_in(node) do
    {_node, lines} =
      Macro.prewalk(node, [], fn
        {_form, meta, _args} = inner, lines ->
          case Keyword.fetch(meta, :line) do
            {:ok, line} -> {inner, [line | lines]}
            :error -> {inner, lines}
          end

        inner, lines ->
          {inner, lines}
      end)

    lines
  end
end
