defmodule Muta.Original do
  alias Muta.Source
  alias Muta.UntrustworthyError

  @enforce_keys [:modules, :source]
  defstruct [:modules, :source]

  @type t :: %__MODULE__{modules: [{module(), binary()}], source: Source.t()}

  @spec compile(Source.t()) :: t()
  def compile(%Source{} = source) do
    modules = Code.compile_string(source.code, Path.expand(source.file))
    Enum.each(modules, fn {module, _binary} -> ensure_expands_nothing(module) end)

    %__MODULE__{modules: modules, source: source}
  end

  defp ensure_expands_nothing(module) do
    module.module_info(:exports)
    |> Enum.filter(fn {name, _arity} -> String.starts_with?(to_string(name), "MACRO-") end)
    |> refuse_macros(module)
  end

  defp refuse_macros([], _module), do: :ok

  defp refuse_macros(_macros, module) do
    raise UntrustworthyError,
          "#{inspect(module)} defines macros, and a macro is expanded into its callers when " <>
            "they compile. Reloading this module alone leaves every caller running the old " <>
            "expansion, so mutants here would be loaded but never executed and every one of " <>
            "them would be reported as surviving."
  end

  @spec restore(t()) :: :ok
  def restore(%__MODULE__{} = original) do
    path = String.to_charlist(original.source.file)

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
