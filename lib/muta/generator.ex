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
      at: index,
      replacement: replacement
    }
  end

  defp line_of({_form, meta, _args}), do: Keyword.fetch!(meta, :line)
end
