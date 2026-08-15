defmodule Muta.Timing.Formatter do
  use GenServer

  alias Muta.Timing

  @impl GenServer
  def init(_opts), do: {:ok, :recording}

  @impl GenServer
  def handle_cast({:test_finished, %ExUnit.Test{time: time}}, state) do
    Timing.record(time)

    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}
end
