defmodule Muta.Timing.Formatter do
  use GenServer

  alias Muta.Timing

  @impl GenServer
  def init(opts), do: {:ok, Keyword.fetch!(opts, :muta_timing)}

  @impl GenServer
  def handle_cast({:test_finished, %ExUnit.Test{time: time}}, timing) do
    Timing.record(timing, time)

    {:noreply, timing}
  end

  def handle_cast(_event, timing), do: {:noreply, timing}
end
