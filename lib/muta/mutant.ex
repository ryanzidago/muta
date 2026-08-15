defmodule Muta.Mutant do
  alias Muta.Mutation

  @enforce_keys [:file, :line, :mutator, :original, :mutated, :outcome, :duration_ms]
  defstruct [:file, :line, :mutator, :original, :mutated, :outcome, :duration_ms]

  @type outcome :: :killed | :survived | :timed_out | :invalid

  @type t :: %__MODULE__{
          file: Path.t(),
          line: pos_integer(),
          mutator: module(),
          original: String.t(),
          mutated: String.t(),
          outcome: outcome(),
          duration_ms: non_neg_integer()
        }

  @spec evaluated(Mutation.t(), outcome(), non_neg_integer()) :: t()
  def evaluated(%Mutation{} = mutation, outcome, duration_ms) do
    %__MODULE__{
      file: mutation.file,
      line: mutation.line,
      mutator: mutation.mutator,
      original: mutation.original,
      mutated: mutation.mutated,
      outcome: outcome,
      duration_ms: duration_ms
    }
  end
end
