defmodule Muta.Mutation do
  @enforce_keys [:file, :line, :mutator, :original, :mutated, :ast]
  defstruct [:file, :line, :mutator, :original, :mutated, :ast]

  @type t :: %__MODULE__{
          file: Path.t(),
          line: pos_integer(),
          mutator: module(),
          original: String.t(),
          mutated: String.t(),
          ast: Macro.t()
        }
end
