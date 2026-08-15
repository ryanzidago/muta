defmodule Muta.Report do
  alias Muta.Mutant

  @enforce_keys [:mutants, :killed, :survived, :invalid, :score]
  defstruct [:mutants, :killed, :survived, :invalid, :score]

  @type t :: %__MODULE__{
          mutants: [Mutant.t()],
          killed: non_neg_integer(),
          survived: non_neg_integer(),
          invalid: non_neg_integer(),
          score: float()
        }

  @spec from_mutants([Mutant.t()]) :: t()
  def from_mutants(mutants) do
    killed = count(mutants, :killed)
    survived = count(mutants, :survived)

    %__MODULE__{
      mutants: mutants,
      killed: killed,
      survived: survived,
      invalid: count(mutants, :invalid),
      score: score(killed, survived)
    }
  end

  @spec survivors(t()) :: [Mutant.t()]
  def survivors(%__MODULE__{mutants: mutants}) do
    Enum.filter(mutants, &(&1.outcome == :survived))
  end

  defp count(mutants, outcome), do: Enum.count(mutants, &(&1.outcome == outcome))

  defp score(0, 0), do: 100.0

  defp score(killed, survived) do
    Float.round(killed * 100 / (killed + survived), 2)
  end
end
