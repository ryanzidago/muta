defmodule Muta.Coverage.Cache do
  alias Muta.Coverage

  @spec fetch(Path.t(), binary()) :: {:ok, Coverage.t()} | :stale
  def fetch(path, fingerprint) do
    with {:ok, binary} <- File.read(path),
         {^fingerprint, coverage} <- :erlang.binary_to_term(binary) do
      {:ok, coverage}
    else
      _anything_else -> :stale
    end
  rescue
    ArgumentError -> :stale
  end

  @spec store(Path.t(), binary(), Coverage.t()) :: :ok
  def store(path, fingerprint, coverage) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary({fingerprint, coverage}))
  end

  @spec fingerprint([Path.t()], [module()]) :: binary()
  def fingerprint(test_files, target_modules) do
    contents = Enum.map(Enum.sort(test_files), &File.read!/1)

    :crypto.hash(:sha256, :erlang.term_to_binary({contents, Enum.sort(target_modules)}))
  end
end
