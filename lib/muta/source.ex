defmodule Muta.Source do
  @enforce_keys [:file, :code, :ast]
  defstruct [:file, :code, :ast]

  @type t :: %__MODULE__{file: Path.t(), code: String.t(), ast: Macro.t()}

  @spec read(Path.t()) :: t()
  def read(file), do: file |> File.read!() |> parse(file)

  @spec parse(String.t(), Path.t()) :: t()
  def parse(code, file) do
    ast = Code.string_to_quoted!(code, file: file, literal_encoder: &locate_atom/2)

    %__MODULE__{file: file, code: code, ast: ast}
  end

  @spec compilable(Macro.t()) :: Macro.t()
  def compilable(ast) do
    Macro.prewalk(ast, fn
      {:__block__, _meta, [atom]} when is_atom(atom) -> atom
      node -> node
    end)
  end

  defp locate_atom(atom, meta) when is_atom(atom), do: {:ok, {:__block__, meta, [atom]}}
  defp locate_atom(literal, _meta), do: {:ok, literal}
end
