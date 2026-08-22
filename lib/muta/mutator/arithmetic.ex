defmodule Muta.Mutator.Arithmetic do
  @behaviour Muta.Mutator

  @swaps %{:+ => :-, :- => :+, :* => :/, :/ => :*}

  @impl Muta.Mutator
  def mutations({operator, meta, [_left, _right] = operands})
      when is_map_key(@swaps, operator) do
    [{@swaps[operator], meta, operands}]
  end

  def mutations(_node), do: []
end
