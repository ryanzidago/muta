defmodule Muta.Coverage.Cache do
  alias Muta.Coverage

  @enforce_keys [:coverage, :files_by_module]
  defstruct [:coverage, :files_by_module]

  @type t :: %__MODULE__{coverage: Coverage.t(), files_by_module: %{module() => Path.t()}}

  @spec fetch(Path.t(), binary()) :: {:ok, t()} | :stale
  def fetch(path, fingerprint) do
    with {:ok, binary} <- File.read(path),
         {^fingerprint, %__MODULE__{} = cache} <- :erlang.binary_to_term(binary) do
      {:ok, cache}
    else
      _anything_else -> :stale
    end
  rescue
    ArgumentError -> :stale
  end

  @spec store(Path.t(), binary(), t()) :: :ok
  def store(path, fingerprint, %__MODULE__{} = cache) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary({fingerprint, cache}))
  end

  @spec fingerprint([Path.t()], [module()]) :: binary()
  def fingerprint(test_files, target_modules) do
    contents = Enum.map(Enum.sort(test_files), &File.read!/1)

    :crypto.hash(:sha256, :erlang.term_to_binary({contents, Enum.sort(target_modules)}))
  end
end
