defmodule Muta.Generator do
  alias Muta.Mutation
  alias Muta.Source

  @spec generate(Source.t(), [module()]) :: [Mutation.t()]
  def generate(%Source{} = source, mutators) do
    source.ast
    |> candidates(mutators)
    |> Enum.map(&build(&1, source))
  end

  defp candidates(ast, mutators) do
    {_ast, {_index, found}} =
      Macro.prewalk(ast, {0, []}, fn node, {index, found} ->
        offered =
          Enum.flat_map(mutators, fn mutator ->
            Enum.map(mutator.mutations(node), &{index, mutator, node, &1})
          end)

        {node, {index + 1, Enum.reverse(offered) ++ found}}
      end)

    Enum.reverse(found)
  end

  defp build({index, mutator, node, replacement}, %Source{} = source) do
    %Mutation{
      file: source.file,
      line: line_of(node),
      mutator: mutator,
      original: Macro.to_string(node),
      mutated: Macro.to_string(replacement),
      ast: replace_at(source.ast, index, replacement)
    }
  end

  defp replace_at(ast, target_index, replacement) do
    {mutated, _index} =
      Macro.prewalk(ast, 0, fn
        _node, index when index == target_index -> {replacement, index + 1}
        node, index -> {node, index + 1}
      end)

    mutated
  end

  defp line_of({_form, meta, _args}), do: Keyword.fetch!(meta, :line)
end
