defmodule Muta.Mutation do
  @enforce_keys [:file, :line, :mutator, :function, :original, :mutated, :at, :replacement]
  defstruct [:file, :line, :mutator, :function, :original, :mutated, :at, :replacement]

  @type t :: %__MODULE__{
          file: Path.t(),
          line: pos_integer(),
          mutator: module(),
          function: String.t(),
          original: String.t(),
          mutated: String.t(),
          at: non_neg_integer(),
          replacement: Macro.t()
        }

  @spec apply_to(t(), Macro.t()) :: Macro.t()
  def apply_to(%__MODULE__{} = mutation, ast) do
    {mutated, _index} =
      Macro.prewalk(ast, 0, fn
        _node, index when index == mutation.at -> {mutation.replacement, index + 1}
        node, index -> {node, index + 1}
      end)

    mutated
  end
end
