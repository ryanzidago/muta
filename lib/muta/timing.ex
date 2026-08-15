defmodule Muta.Timing do
  use Agent

  def start_link, do: Agent.start_link(fn -> 0 end, name: __MODULE__)

  def record(microseconds), do: Agent.update(__MODULE__, &max(&1, microseconds))

  def slowest_ms, do: div(Agent.get(__MODULE__, & &1), 1000)

  def stop, do: Agent.stop(__MODULE__)
end
