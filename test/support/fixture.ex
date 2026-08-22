defmodule Muta.Support.Fixture do
  alias Muta.Config

  def config(dir, name, source, suite, opts \\ []) do
    Config.new(
      [target(dir, name, source)],
      [test_file(dir, name, suite)],
      Keyword.merge([workers: 1, test_helper: helper(dir)], opts)
    )
  end

  def target(dir, name, source) do
    file = Path.join(dir, "#{name}.ex")
    File.write!(file, source)
    Code.compile_string(source, file)

    file
  end

  def test_file(dir, name, suite) do
    file = Path.join(dir, "#{name}_test.exs")
    File.write!(file, suite)

    file
  end

  def helper(dir) do
    file = Path.join(dir, "test_helper.exs")
    File.write!(file, "ExUnit.start(autorun: false)\n")

    file
  end

  def tmp_dir do
    dir = Path.join(System.tmp_dir!(), "muta-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    dir
  end
end
