defmodule Muta.Source do
  @enforce_keys [:file, :code, :ast]
  defstruct [:file, :code, :ast]

  @type t :: %__MODULE__{file: Path.t(), code: String.t(), ast: Macro.t()}

  @spec read(Path.t()) :: t()
  def read(file), do: file |> File.read!() |> parse(file)

  @spec parse(String.t(), Path.t()) :: t()
  def parse(code, file) do
    %__MODULE__{file: file, code: code, ast: Code.string_to_quoted!(code, file: file)}
  end
end
