defmodule Muta.ConfigTest do
  use ExUnit.Case, async: false

  alias Muta.Config
  alias Muta.Support.Fixture

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    dir = Fixture.tmp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir}
  end

  defp source(dir) do
    Fixture.target(dir, "priced", "defmodule Priced do\n  def free?(n), do: n > 0\nend\n")
  end

  test "refuses a worker count that would leave every mutant unjudged", %{dir: dir} do
    assert_raise ArgumentError, ~r/at least one worker/, fn ->
      Config.new([source(dir)], [], workers: 0)
    end
  end

  test "refuses a worker count that is not a number at all", %{dir: dir} do
    assert_raise ArgumentError, ~r/at least one worker/, fn ->
      Config.new([source(dir)], [], workers: "many")
    end
  end

  test "takes a worker count the caller asks for", %{dir: dir} do
    assert %Config{workers: 3} = Config.new([source(dir)], [], workers: 3)
  end

  test "raises when a source file does not exist" do
    assert_raise File.Error, fn -> Config.new(["does/not/exist.ex"], []) end
  end
end
