defmodule Muta.Mutator.Boundary do
  @behaviour Muta.Mutator

  @orderings %{:> => 1, :<= => 1, :>= => -1, :< => -1}
  @equalities [:==, :!=, :===, :!==]

  @impl Muta.Mutator
  def mutations({operator, meta, [left, right]}) when is_map_key(@orderings, operator) do
    shift = @orderings[operator]

    rebuilt({operator, meta, [left, right]}, [-shift], [shift])
  end

  def mutations({operator, meta, [left, right]}) when operator in @equalities do
    rebuilt({operator, meta, [left, right]}, [-1, 1], [-1, 1])
  end

  def mutations(_node), do: []

  defp rebuilt({operator, meta, [left, right]}, on_left, on_right) do
    Enum.map(shifted(left, on_left), &{operator, meta, [&1, right]}) ++
      Enum.map(shifted(right, on_right), &{operator, meta, [left, &1]})
  end

  defp shifted(operand, shifts) when is_integer(operand), do: Enum.map(shifts, &(operand + &1))
  defp shifted(_operand, _shifts), do: []
end
