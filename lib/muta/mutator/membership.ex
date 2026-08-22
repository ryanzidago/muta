defmodule Muta.Mutator.Membership do
  @behaviour Muta.Mutator

  @impl Muta.Mutator
  def mutations({:in, meta, [_element, _collection]} = node) do
    [{:not, meta, [node]}]
  end

  def mutations(_node), do: []
end
