defmodule Muta.Report do
  alias Muta.Mutant

  @enforce_keys [
    :files,
    :mutants,
    :killed,
    :survived,
    :accepted,
    :unstable,
    :invalid,
    :skipped,
    :score
  ]
  defstruct [
    :files,
    :mutants,
    :killed,
    :survived,
    :accepted,
    :unstable,
    :invalid,
    :skipped,
    :score
  ]

  @type t :: %__MODULE__{
          files: [Path.t()],
          mutants: [Mutant.t()],
          killed: non_neg_integer(),
          survived: non_neg_integer(),
          accepted: non_neg_integer(),
          unstable: non_neg_integer(),
          invalid: non_neg_integer(),
          skipped: non_neg_integer(),
          score: float()
        }

  @spec from_mutants([Mutant.t()], [Path.t()], non_neg_integer()) :: t()
  def from_mutants(mutants, files, skipped \\ 0) do
    killed = count(mutants, :killed)
    survived = count(mutants, :survived)

    %__MODULE__{
      files: files,
      mutants: mutants,
      killed: killed,
      survived: survived,
      accepted: count(mutants, :accepted),
      unstable: count(mutants, :unstable),
      invalid: count(mutants, :invalid),
      skipped: skipped,
      score: score(killed, survived)
    }
  end

  @spec survivors(t()) :: [Mutant.t()]
  def survivors(%__MODULE__{} = report), do: with_outcome(report, :survived)

  @spec accepted(t()) :: [Mutant.t()]
  def accepted(%__MODULE__{} = report), do: with_outcome(report, :accepted)

  @spec unstable(t()) :: [Mutant.t()]
  def unstable(%__MODULE__{} = report), do: with_outcome(report, :unstable)

  @spec invalid(t()) :: [Mutant.t()]
  def invalid(%__MODULE__{} = report), do: with_outcome(report, :invalid)

  @spec unexercised(t()) :: [{Path.t(), String.t()}]
  def unexercised(%__MODULE__{mutants: mutants}) do
    mutants
    |> Enum.group_by(&{&1.file, &1.function})
    |> Enum.filter(fn {_where, of_function} -> unexercised?(of_function) end)
    |> Enum.map(fn {where, _of_function} -> where end)
    |> Enum.sort()
  end

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

  defp unexercised?(mutants) do
    Enum.any?(mutants, &(&1.outcome == :survived)) and
      not Enum.any?(mutants, &(&1.outcome == :killed))
  end

  defp count(mutants, outcome), do: Enum.count(mutants, &(&1.outcome == outcome))

  defp score(0, 0), do: 100.0

  defp score(killed, survived) do
    Float.round(killed * 100 / (killed + survived), 2)
  end
end
