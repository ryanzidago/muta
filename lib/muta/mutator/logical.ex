defmodule Muta.Mutator.Logical do
  @behaviour Muta.Mutator

  @swaps %{:&& => :||, :|| => :&&, :and => :or, :or => :and}

  @impl Muta.Mutator
  def mutations({operator, meta, [_left, _right] = operands})
      when is_map_key(@swaps, operator) do
    [{@swaps[operator], meta, operands}]
  end

  def mutations({negation, _meta, [{:in, _in_meta, [_element, _collection]}]})
      when negation in [:not, :!] do
    []
  end

  def mutations({negation, _meta, [negated]}) when negation in [:not, :!] do
    [negated]
  end

  def mutations(_node), do: []
end
