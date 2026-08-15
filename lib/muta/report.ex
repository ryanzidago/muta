defmodule Muta.Report do
  alias Muta.Mutant

  @enforce_keys [:mutants, :killed, :survived, :timed_out, :invalid, :score]
  defstruct [:mutants, :killed, :survived, :timed_out, :invalid, :score]

  @type t :: %__MODULE__{
          mutants: [Mutant.t()],
          killed: non_neg_integer(),
          survived: non_neg_integer(),
          timed_out: non_neg_integer(),
          invalid: non_neg_integer(),
          score: float()
        }

  @spec from_mutants([Mutant.t()]) :: t()
  def from_mutants(mutants) do
    killed = count(mutants, :killed)
    survived = count(mutants, :survived)
    timed_out = count(mutants, :timed_out)

    %__MODULE__{
      mutants: mutants,
      killed: killed,
      survived: survived,
      timed_out: timed_out,
      invalid: count(mutants, :invalid),
      score: score(killed + timed_out, survived)
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
