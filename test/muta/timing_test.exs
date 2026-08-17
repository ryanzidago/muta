defmodule Muta.TimingTest do
  use ExUnit.Case, async: true

  alias Muta.Timing

  test "reports the slowest test it saw, in milliseconds" do
    {:ok, timing} = Timing.start_link()

    Timing.record(timing, 1_000)
    Timing.record(timing, 5_000)
    Timing.record(timing, 2_000)

    assert Timing.slowest_ms(timing) == 5

    Timing.stop(timing)
  end

  test "reports zero before anything has been recorded" do
    {:ok, timing} = Timing.start_link()

    assert Timing.slowest_ms(timing) == 0

    Timing.stop(timing)
  end
end
