defmodule Muta.SettingsTest do
  use ExUnit.Case, async: false

  alias Muta.Settings

  @borrowed [:formatters, :max_failures, :muta_timing, :only_test_ids, :timeout]

  defp borrowed do
    config = ExUnit.configuration()

    {Enum.map(@borrowed, &{&1, config[&1]}), Code.get_compiler_option(:ignore_module_conflict)}
  end

  test "gives back every setting the work changed" do
    before = borrowed()

    Settings.restored_after(fn ->
      Code.put_compiler_option(:ignore_module_conflict, true)

      ExUnit.configure(
        formatters: [Muta.Timing.Formatter],
        max_failures: 7,
        muta_timing: self(),
        only_test_ids: MapSet.new([{SomeTest, :"test thing"}]),
        timeout: 12_345
      )
    end)

    assert borrowed() == before
  end

  test "gives them back even when the work raises" do
    before = borrowed()

    assert_raise RuntimeError, fn ->
      Settings.restored_after(fn ->
        ExUnit.configure(max_failures: 99, timeout: 1)
        Code.put_compiler_option(:ignore_module_conflict, true)

        raise "work blew up"
      end)
    end

    assert borrowed() == before
  end
end
