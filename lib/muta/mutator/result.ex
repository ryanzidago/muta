defmodule Muta.Mutator.Result do
  @behaviour Muta.Mutator

  @swaps %{ok: :error, error: :ok}

  @impl Muta.Mutator
  def mutations({:__block__, meta, [tag]}) when is_map_key(@swaps, tag) do
    [{:__block__, meta, [@swaps[tag]]}]
  end

  def mutations(_node), do: []
end
