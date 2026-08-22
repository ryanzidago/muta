defmodule Muta.Mutator.Boolean do
  @behaviour Muta.Mutator

  @swaps %{true => false, false => true}

  @impl Muta.Mutator
  def mutations({:__block__, meta, [literal]}) when is_map_key(@swaps, literal) do
    [{:__block__, meta, [@swaps[literal]]}]
  end

  def mutations(_node), do: []
end
