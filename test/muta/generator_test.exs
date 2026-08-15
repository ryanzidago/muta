defmodule Muta.GeneratorTest do
  use ExUnit.Case, async: true

  alias Muta.Generator
  alias Muta.Mutator.Comparison
  alias Muta.Source

  defp generate(code), do: Generator.generate(Source.parse(code, "example.ex"), [Comparison])

  test "records where each mutation applies and what it changes" do
    source = ~S"""
    defmodule Example do
      def sign(n) when n < 0, do: :negative
    end
    """

    assert [boundary, inverse] = generate(source)

    assert boundary.file == "example.ex"
    assert boundary.line == 2
    assert boundary.mutator == Comparison
    assert boundary.original == "n < 0"
    assert boundary.mutated == "n <= 0"

    assert inverse.mutated == "n > 0"
  end

  test "produces one mutation per replacement across every comparison" do
    source = ~S"""
    defmodule Example do
      def check(a, b) do
        a < b and a == b
      end
    end
    """

    assert Enum.map(generate(source), & &1.mutated) == [
             "a <= b",
             "a > b",
             "a != b"
           ]
  end

  test "each mutation carries a full syntax tree with only its own node changed" do
    source = ~S"""
    defmodule Example do
      def sign(n) when n < 0, do: :negative
    end
    """

    [boundary, _inverse] = generate(source)
    mutated_source = Macro.to_string(boundary.ast)

    assert mutated_source =~ "n <= 0"
    refute mutated_source =~ "n < 0"
    assert mutated_source =~ ":negative"
  end

  test "leaves a source with nothing to mutate alone" do
    source = ~S"""
    defmodule Example do
      def shout(word), do: String.upcase(word)
    end
    """

    assert generate(source) == []
  end

  test "raises when the source cannot be parsed" do
    assert_raise TokenMissingError, fn -> generate("defmodule Broken do") end
  end
end
