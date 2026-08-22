defmodule Muta.Mutant do
  alias Muta.Mutation

  @enforce_keys [:file, :line, :mutator, :original, :mutated, :outcome]
  defstruct [:file, :line, :mutator, :original, :mutated, :outcome]

  @type outcome :: :killed | :survived | :unstable | :invalid

  @type t :: %__MODULE__{
          file: Path.t(),
          line: pos_integer(),
          mutator: module(),
          original: String.t(),
          mutated: String.t(),
          outcome: outcome()
        }

  @spec evaluated(Mutation.t(), outcome()) :: t()
  def evaluated(%Mutation{} = mutation, outcome) do
    %__MODULE__{
      file: mutation.file,
      line: mutation.line,
      mutator: mutation.mutator,
      original: mutation.original,
      mutated: mutation.mutated,
      outcome: outcome
    }
  end
end
