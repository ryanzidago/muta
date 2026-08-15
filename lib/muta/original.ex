defmodule Muta.Original do
  alias Muta.Source
  alias Muta.UntrustworthyError

  @enforce_keys [:modules, :file]
  defstruct [:modules, :file]

  @type t :: %__MODULE__{modules: [{module(), binary()}], file: Path.t()}

  @spec compile(Source.t()) :: t()
  def compile(%Source{} = source) do
    %__MODULE__{modules: Code.compile_string(source.code, source.file), file: source.file}
  end

  @spec restore(t()) :: :ok
  def restore(%__MODULE__{} = original) do
    path = String.to_charlist(original.file)

    Enum.each(original.modules, fn {module, binary} -> :code.load_binary(module, path, binary) end)
  end

  @spec reclaim(t()) :: :ok
  def reclaim(%__MODULE__{} = original) do
    Enum.each(original.modules, fn {module, _binary} -> ensure_nothing_still_runs(module) end)
  end

  defp ensure_nothing_still_runs(module) do
    if :code.soft_purge(module) do
      :ok
    else
      raise UntrustworthyError,
            "a process is still running mutated #{inspect(module)} code after its test " <>
              "finished. The next mutant would be judged partly against this one, so the " <>
              "run stops here rather than reporting a verdict shaped by it."
    end
  end
end
