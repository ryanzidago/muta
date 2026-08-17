defmodule Muta.Support.IllegalInGuard do
  @behaviour Muta.Mutator

  @impl Muta.Mutator
  def mutations({:<, meta, [left, right]}) do
    [{{:., meta, [IO, :inspect]}, meta, [left, right]}]
  end

  def mutations(_node), do: []
end
