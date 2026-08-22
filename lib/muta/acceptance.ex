defmodule Muta.Acceptance do
  alias Muta.Mutant

  @enforce_keys [:file, :original, :mutated, :reason]
  defstruct [:file, :original, :mutated, :reason]

  @type t :: %__MODULE__{
          file: Path.t(),
          original: String.t(),
          mutated: String.t(),
          reason: String.t()
        }

  @spec read(Path.t()) :: [t()]
  def read(path), do: path |> File.exists?() |> recorded_in(path)

  @spec apply_to([t()], [Mutant.t()]) :: [Mutant.t()]
  def apply_to(acceptances, mutants), do: Enum.map(mutants, &classify(&1, acceptances))

  @spec reason_for([t()], Mutant.t()) :: String.t()
  def reason_for(acceptances, %Mutant{} = mutant) do
    acceptances |> Enum.find(&matches?(&1, mutant)) |> reason()
  end

  @spec unused([t()], [Mutant.t()]) :: [t()]
  def unused(acceptances, mutants) do
    Enum.reject(acceptances, fn acceptance ->
      Enum.any?(mutants, &matches?(acceptance, &1))
    end)
  end

  defp recorded_in(false, _path), do: []

  defp recorded_in(true, path) do
    path |> Code.eval_file() |> elem(0) |> entries(path) |> Enum.map(&build(&1, path))
  end

  defp entries(entries, _path) when is_list(entries), do: entries

  defp entries(other, path) do
    raise ArgumentError,
          "#{path} must return a list of accepted mutants, got #{inspect(other)}. " <>
            "An accepted mutant is a map with :file, :original, :mutated and :reason."
  end

  defp build(%{file: file, original: original, mutated: mutated, reason: reason}, _path)
       when is_binary(file) and is_binary(original) and is_binary(mutated) and
              is_binary(reason) and reason != "" do
    %__MODULE__{
      file: Path.expand(file),
      original: flattened(original),
      mutated: flattened(mutated),
      reason: reason
    }
  end

  defp build(entry, path) do
    raise ArgumentError,
          "#{path} holds an entry muta cannot read: #{inspect(entry)}. " <>
            "Every entry needs :file, :original, :mutated and a non-empty :reason, " <>
            "all strings. The reason is required because an accepted mutant is a " <>
            "claim that no test could ever kill it, and the next reader has to be " <>
            "able to check that claim."
  end

  defp classify(%Mutant{outcome: :survived} = mutant, acceptances) do
    accepted(mutant, Enum.any?(acceptances, &matches?(&1, mutant)))
  end

  defp classify(%Mutant{} = mutant, _acceptances), do: mutant

  defp accepted(%Mutant{} = mutant, true), do: %{mutant | outcome: :accepted}
  defp accepted(%Mutant{} = mutant, false), do: mutant

  defp matches?(%__MODULE__{} = acceptance, %Mutant{} = mutant) do
    acceptance.file == Path.expand(mutant.file) and
      acceptance.original == flattened(mutant.original) and
      acceptance.mutated == flattened(mutant.mutated)
  end

  defp flattened(source), do: source |> String.split() |> Enum.join(" ")

  defp reason(%__MODULE__{reason: reason}), do: reason
end
