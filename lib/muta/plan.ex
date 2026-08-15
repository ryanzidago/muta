defmodule Muta.Plan do
  alias Muta.Coverage
  alias Muta.Mutation
  alias Muta.Source

  @enforce_keys [:mutation, :rounds]
  defstruct [:mutation, :rounds]

  @type t :: %__MODULE__{mutation: Mutation.t(), rounds: [[Coverage.test_id()]]}

  @spec for_mutations([Mutation.t()], Source.t(), Coverage.t()) :: [t()]
  def for_mutations(mutations, %Source{} = source, coverage) do
    focus = Coverage.focus(coverage, source.modules)

    Enum.map(mutations, fn mutation ->
      %__MODULE__{mutation: mutation, rounds: rounds(mutation, source, coverage, focus)}
    end)
  end

  @spec first_round(t()) :: [Coverage.test_id()]
  def first_round(%__MODULE__{rounds: []}), do: []
  def first_round(%__MODULE__{rounds: [first | _later]}), do: first

  @spec later_rounds(t()) :: [[Coverage.test_id()]]
  def later_rounds(%__MODULE__{rounds: []}), do: []
  def later_rounds(%__MODULE__{rounds: [_first | later]}), do: later

  defp rounds(%Mutation{} = mutation, %Source{} = source, coverage, focus) do
    case Map.fetch(source.functions_by_line, mutation.line) do
      {:ok, signature} ->
        coverage
        |> Coverage.tests_covering(source.modules, signature)
        |> closest_first(focus)

      :error ->
        []
    end
  end

  defp closest_first(test_ids, focus) do
    test_ids
    |> Enum.group_by(fn {test_module, _name} -> test_module end)
    |> Enum.sort_by(fn {test_module, ids} -> {-Map.get(focus, test_module, 0), length(ids)} end)
    |> split_off_closest()
  end

  defp split_off_closest([]), do: []
  defp split_off_closest([{_test_module, closest}]), do: [closest]

  defp split_off_closest([{_test_module, closest} | rest]) do
    [closest, Enum.flat_map(rest, fn {_test_module, ids} -> ids end)]
  end
end
