defmodule Muta.Mutator.Condition do
  @behaviour Muta.Mutator

  @impl Muta.Mutator
  def mutations({branch, meta, [_condition, bodies]}) when branch in [:if, :unless] do
    [{branch, meta, [true, bodies]}, {branch, meta, [false, bodies]}]
  end

  def mutations(_node), do: []
end
