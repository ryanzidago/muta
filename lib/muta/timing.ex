defmodule Muta.Timing do
  @spec start_link() :: {:ok, pid()}
  def start_link, do: Agent.start_link(fn -> 0 end)

  @spec record(pid(), non_neg_integer()) :: :ok
  def record(timing, microseconds), do: Agent.update(timing, &max(&1, microseconds))

  @spec slowest_ms(pid()) :: non_neg_integer()
  def slowest_ms(timing), do: div(Agent.get(timing, & &1), 1000)

  @spec stop(pid()) :: :ok
  def stop(timing), do: Agent.stop(timing)
end
