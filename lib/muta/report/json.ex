defmodule Muta.Report.Json do
  alias Muta.Mutant
  alias Muta.Report

  @spec encode(Report.t()) :: String.t()
  def encode(%Report{} = report) do
    JSON.encode!(%{
      "score" => report.score,
      "files" => Enum.sort(report.files),
      "totals" => totals(report),
      "mutants" => Enum.map(sorted(report.mutants), &mutant/1),
      "unexercised" => Enum.map(Report.unexercised(report), &unexercised/1)
    })
  end

  defp totals(%Report{} = report) do
    %{
      "mutants" => length(report.mutants),
      "killed" => report.killed,
      "survived" => report.survived,
      "accepted" => report.accepted,
      "unstable" => report.unstable,
      "invalid" => report.invalid,
      "skipped" => report.skipped,
      "in_type_guards" => report.in_type_guards
    }
  end

  defp mutant(%Mutant{} = mutant) do
    %{
      "file" => mutant.file,
      "line" => mutant.line,
      "outcome" => Atom.to_string(mutant.outcome),
      "mutator" => mutant.mutator |> Module.split() |> List.last(),
      "function" => mutant.function,
      "original" => mutant.original,
      "mutated" => mutant.mutated
    }
  end

  defp unexercised({file, function}), do: %{"file" => file, "function" => function}

  defp sorted(mutants), do: Enum.sort_by(mutants, &{&1.file, &1.line, &1.mutated})
end
