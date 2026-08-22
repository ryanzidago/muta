defmodule Muta.Report do
  alias Muta.Mutant

  @enforce_keys [:files, :mutants, :killed, :survived, :unstable, :invalid, :score]
  defstruct [:files, :mutants, :killed, :survived, :unstable, :invalid, :score]

  @type t :: %__MODULE__{
          files: [Path.t()],
          mutants: [Mutant.t()],
          killed: non_neg_integer(),
          survived: non_neg_integer(),
          unstable: non_neg_integer(),
          invalid: non_neg_integer(),
          score: float()
        }

  @spec from_mutants([Mutant.t()], [Path.t()]) :: t()
  def from_mutants(mutants, files) do
    killed = count(mutants, :killed)
    survived = count(mutants, :survived)

    %__MODULE__{
      files: files,
      mutants: mutants,
      killed: killed,
      survived: survived,
      unstable: count(mutants, :unstable),
      invalid: count(mutants, :invalid),
      score: score(killed, survived)
    }
  end

  @spec survivors(t()) :: [Mutant.t()]
  def survivors(%__MODULE__{} = report), do: with_outcome(report, :survived)

  @spec unstable(t()) :: [Mutant.t()]
  def unstable(%__MODULE__{} = report), do: with_outcome(report, :unstable)

  @spec by_file(t()) :: [{Path.t(), t()}]
  def by_file(%__MODULE__{files: files, mutants: mutants}) do
    of_file = Enum.group_by(mutants, & &1.file)

    files
    |> Enum.sort()
    |> Enum.map(fn file -> {file, from_mutants(Map.get(of_file, file, []), [file])} end)
  end

  defp with_outcome(%__MODULE__{mutants: mutants}, outcome) do
    mutants
    |> Enum.filter(&(&1.outcome == outcome))
    |> Enum.sort_by(&{&1.file, &1.line, &1.mutated})
  end

  defp count(mutants, outcome), do: Enum.count(mutants, &(&1.outcome == outcome))

  defp score(0, 0), do: 100.0

  defp score(killed, survived) do
    Float.round(killed * 100 / (killed + survived), 2)
  end
end
