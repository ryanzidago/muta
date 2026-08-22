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

  @type_predicates [
    :is_atom,
    :is_binary,
    :is_bitstring,
    :is_boolean,
    :is_float,
    :is_function,
    :is_integer,
    :is_list,
    :is_map,
    :is_nil,
    :is_number,
    :is_pid,
    :is_port,
    :is_reference,
    :is_struct,
    :is_tuple
  ]

  @conjunctions [:and, :or, :&&, :||]
  @outside_any_function "(top level)"

  @spec generate(Source.t(), [module()]) :: [Mutation.t()]
  def generate(%Source{} = source, mutators) do
    source.ast
    |> candidates(mutators)
    |> Enum.map(&build(&1, source))
  end

  defp candidates(ast, mutators) do
    {_ast, %{found: found}} =
      Macro.traverse(ast, blank(), &enter(&1, &2, mutators), &leave/2)

    Enum.reverse(found)
  end

  defp blank, do: %{index: 0, found: [], annotations: 0, guards: 0, functions: []}

  defp enter(node, context, mutators) do
    context = %{
      context
      | annotations: context.annotations + annotation(node),
        guards: context.guards + guard(node),
        functions: push(definition(node), context.functions)
    }

    {node,
     %{
       context
       | index: context.index + 1,
         found: offers(node, context, mutators) ++ context.found
     }}
  end

  defp leave(node, context) do
    {node,
     %{
       context
       | annotations: context.annotations - annotation(node),
         guards: context.guards - guard(node),
         functions: pop(definition(node), context.functions)
     }}
  end

  defp offers(_node, %{annotations: annotations}, _mutators) when annotations > 0, do: []

  defp offers(node, context, mutators) do
    if context.guards > 0 and type_check?(node) do
      []
    else
      mutators
      |> Enum.flat_map(fn mutator ->
        Enum.map(
          mutator.mutations(node),
          &{context.index, line_of(node), mutator, node, &1, enclosing(context.functions)}
        )
      end)
      |> Enum.reverse()
    end
  end

  defp annotation({:@, _meta, [{name, _name_meta, _args}]}) when name in @annotations, do: 1
  defp annotation(_node), do: 0

  defp guard({:when, _meta, [_head, _condition]}), do: 1
  defp guard(_node), do: 0

  defp definition({kind, _meta, [head | _body]}) when kind in [:def, :defp], do: [signature(head)]
  defp definition(_node), do: []

  defp signature({:when, _meta, [head, _condition]}), do: signature(head)
  defp signature({name, _meta, args}) when is_list(args), do: "#{name}/#{length(args)}"
  defp signature({name, _meta, _args}), do: "#{name}/0"

  defp push([], functions), do: functions
  defp push([signature], functions), do: [signature | functions]

  defp pop([], functions), do: functions
  defp pop([_signature], [_top | rest]), do: rest
  defp pop([_signature], []), do: []

  defp enclosing([]), do: @outside_any_function
  defp enclosing([signature | _rest]), do: signature

  defp type_check?({conjunction, _meta, [left, right]}) when conjunction in @conjunctions,
    do: type_check?(left) and type_check?(right)

  defp type_check?({predicate, _meta, args}) when predicate in @type_predicates and is_list(args),
    do: true

  defp type_check?(_node), do: false

  defp build({index, line, mutator, node, replacement, function}, %Source{} = source) do
    %Mutation{
      file: source.file,
      line: line,
      mutator: mutator,
      function: function,
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
