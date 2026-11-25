defmodule Muta.Report.Json do
  alias Muta.Mutant
  alias Muta.Mutation
  alias Muta.Report

  @spec encode(Report.t()) :: String.t()
  def encode(%Report{} = report) do
    JSON.encode!(%{
      "complete" => report.complete?,
      "score" => report.score,
      "files" => Enum.sort(report.files),
      "totals" => totals(report),
      "mutants" => Enum.map(sorted(report.mutants), &mutant/1),
      "failures" => Enum.map(report.failures, &failure/1),
      "pending" => Enum.map(report.pending, &mutation/1),
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
      "in_type_guards" => report.in_type_guards,
      "unjudged" => length(report.failures) + length(report.pending)
    }
  end

  defp mutant(%Mutant{} = mutant) do
    mutant
    |> identity()
    |> Map.put("outcome", Atom.to_string(mutant.outcome))
  end

  defp failure(%{mutation: %Mutation{} = mutation, reason: reason}) do
    mutation |> mutation_identity() |> Map.put("reason", reason)
  end

  defp mutation(%Mutation{} = mutation), do: mutation_identity(mutation)

  defp identity(mutation) do
    %{
      "file" => mutation.file,
      "line" => mutation.line,
      "mutator" => mutation.mutator |> Module.split() |> List.last(),
      "function" => mutation.function,
      "original" => mutation.original,
      "mutated" => mutation.mutated
    }
  end

  defp mutation_identity(%Mutation{} = mutation) do
    mutation |> identity() |> Map.put("at", mutation.at)
  end

  defp unexercised({file, function}), do: %{"file" => file, "function" => function}

  defp sorted(mutants), do: Enum.sort_by(mutants, &{&1.file, &1.line, &1.mutated})
end
