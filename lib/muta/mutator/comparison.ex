defmodule Muta.Mutator.Comparison do
  @behaviour Muta.Mutator

  @swaps %{
    :< => [:<=, :>],
    :<= => [:<, :>=],
    :> => [:>=, :<],
    :>= => [:>, :<=],
    :== => [:!=],
    :!= => [:==],
    :=== => [:!==],
    :!== => [:===]
  }

  @impl Muta.Mutator
  def mutations({operator, meta, [_left, _right] = operands})
      when is_map_key(@swaps, operator) do
    Enum.map(@swaps[operator], fn replacement -> {replacement, meta, operands} end)
  end

  def mutations(_node), do: []
end
