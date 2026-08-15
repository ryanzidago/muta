defmodule Muta.Support.Fixture do
  alias Muta.Config
  alias Muta.Target

  def config(dir, name, source, suite, opts \\ []) do
    Config.new([target(dir, name, source)], [suite_module(suite)], opts)
  end

  def target(dir, name, source) do
    file = Path.join(dir, "#{name}.ex")
    File.write!(file, source)

    Code.prepend_path(dir)
    Code.put_compiler_option(:debug_info, true)

    source
    |> Code.compile_string(file)
    |> Enum.each(fn {module, binary} ->
      File.write!(Path.join(dir, "#{module}.beam"), binary)
      :code.purge(module)
      {:module, ^module} = :code.load_file(module)
    end)

    %Target{file: file}
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
