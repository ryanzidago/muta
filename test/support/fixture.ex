defmodule Muta.Support.Fixture do
  alias Muta.Config

  def config(dir, name, source, suite, opts \\ []) do
    Config.new([target(dir, name, source)], [suite_module(suite)], opts)
  end

  def target(dir, name, source) do
    file = Path.join(dir, "#{name}.ex")
    File.write!(file, source)
    Code.compile_string(source, file)

    file
  end

  def suite_module(suite) do
    [{test_module, _binary} | _rest] = Code.compile_string(suite)
    test_module
  end

  def tmp_dir do
    dir = Path.join(System.tmp_dir!(), "muta-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end
end
