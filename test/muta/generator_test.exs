defmodule Muta.GeneratorTest do
  use ExUnit.Case, async: true

  alias Muta.Generator
  alias Muta.Mutation
  alias Muta.Mutator.Boolean
  alias Muta.Mutator.Comparison
  alias Muta.Mutator.Condition
  alias Muta.Mutator.Logical
  alias Muta.Mutator.Membership
  alias Muta.Mutator.Result
  alias Muta.Source

  defp generate(code), do: mutations(Source.parse(code, "example.ex"), [Comparison])

  defp mutations(%Source{} = source, mutators) do
    {found, _in_type_guards} = Generator.generate(source, mutators)

    found
  end

  defp in_type_guards(%Source{} = source, mutators) do
    {_found, in_type_guards} = Generator.generate(source, mutators)

    in_type_guards
  end

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

    mutated_source =
      boundary
      |> Mutation.apply_to(Source.parse(source, "example.ex").ast)
      |> Macro.to_string()

    assert mutated_source =~ "n <= 0"
    refute mutated_source =~ "n < 0"
    assert mutated_source =~ ":negative"
  end

  test "reports the line a literal sits on, not the line of the code around it" do
    source = ~S"""
    defmodule Example do
      def fetch(id) do
        if id do
          {:ok, id}
        else
          :error
        end
      end
    end
    """

    located =
      source
      |> Source.parse("example.ex")
      |> mutations([Result])
      |> Enum.map(&{&1.original, &1.line})

    assert located == [{":ok", 4}, {":error", 6}]
  end

  test "skips a node that carries no line when working out where a mutation lands" do
    source = ~S"""
    defmodule Example do
      def pending(list, showing?) do
        if showing? do
          Enum.filter(list, &(!&1.done))
        end
      end
    end
    """

    lines =
      source
      |> Source.parse("example.ex")
      |> mutations([Condition])
      |> Enum.map(& &1.line)

    assert lines == [3, 3]
  end

  test "offers one mutation where two mutators could each claim the same code" do
    source = ~S"""
    defmodule Example do
      def blocked?(role), do: role not in [:owner]
    end
    """

    assert [mutation] =
             mutations(Source.parse(source, "example.ex"), [Logical, Membership])

    assert mutation.mutator == Membership
    assert mutation.original == "role in [:owner]"
  end

  test "leaves type and doc annotations alone, since they never reach runtime" do
    source = ~S"""
    defmodule Example do
      @moduledoc "a gate, open above 10"
      @type outcome :: :ok | :error

      @doc "true above the threshold"
      @spec open?(integer()) :: :ok | :error
      def open?(n) when n > 10, do: :ok
      def open?(_n), do: :error
    end
    """

    mutated =
      source
      |> Source.parse("example.ex")
      |> mutations([Comparison, Result])
      |> Enum.map(& &1.mutated)

    assert mutated == ["n >= 10", "n < 10", ":error", ":ok"]
  end

  test "leaves an impl annotation alone" do
    source = ~S"""
    defmodule Example do
      @behaviour Muta.Mutator

      @impl true
      def mutations(_node), do: []
    end
    """

    assert mutations(Source.parse(source, "example.ex"), [Boolean]) == []
  end

  test "leaves a conjunction of type checks in a guard alone, since no test can tell" do
    source = ~S"""
    defmodule Example do
      def fetch(id, scope) when is_binary(id) and is_binary(scope), do: :ok
      def fetch(_id, _scope), do: :error
    end
    """

    assert mutations(Source.parse(source, "example.ex"), [Logical]) == []
  end

  test "counts the mutants it did not generate inside a type guard" do
    source = ~S"""
    defmodule Example do
      def fetch(id, scope) when is_binary(id) and is_binary(scope), do: :ok
      def fetch(_id, _scope), do: :error
    end
    """

    assert in_type_guards(Source.parse(source, "example.ex"), [Logical]) == 1
  end

  test "counts nothing when no type guard suppressed a mutant" do
    source = ~S"""
    defmodule Example do
      def adult?(age) when age >= 18, do: true
    end
    """

    assert in_type_guards(Source.parse(source, "example.ex"), [Comparison]) == 0
  end

  test "still mutates a comparison sitting in a guard" do
    source = ~S"""
    defmodule Example do
      def adult?(age) when age >= 18, do: true
    end
    """

    mutated =
      source
      |> Source.parse("example.ex")
      |> mutations([Comparison])
      |> Enum.map(& &1.mutated)

    assert mutated == ["age > 18", "age <= 18"]
  end

  test "still mutates a conjunction of type checks outside a guard" do
    source = ~S"""
    defmodule Example do
      def pair?(a, b), do: is_binary(a) and is_binary(b)
    end
    """

    mutated =
      source
      |> Source.parse("example.ex")
      |> mutations([Logical])
      |> Enum.map(& &1.mutated)

    assert mutated == ["is_binary(a) or is_binary(b)"]
  end

  test "still mutates a guard mixing a type check with a comparison" do
    source = ~S"""
    defmodule Example do
      def ready?(items, age) when is_list(items) and age >= 18, do: :ok
    end
    """

    mutated =
      source
      |> Source.parse("example.ex")
      |> mutations([Logical])
      |> Enum.map(& &1.mutated)

    assert mutated == ["is_list(items) or age >= 18"]
  end

  test "records the function each mutation sits in" do
    source = ~S"""
    defmodule Example do
      def free_shipping?(cents), do: cents > 5000
      defp discounted?(cents, rate) when rate > 0, do: cents > 100
    end
    """

    assert [shipping, guard, discount] =
             mutations(Source.parse(source, "example.ex"), [Comparison])
             |> Enum.filter(&(&1.mutated =~ ">="))

    assert shipping.function == "free_shipping?/1"
    assert guard.function == "discounted?/2"
    assert discount.function == "discounted?/2"
  end

  test "leaves a source with nothing to mutate alone" do
    source = ~S"""
    defmodule Example do
      def label(word), do: word <> "!"
    end
    """

    assert generate(source) == []
  end

  test "raises when the source cannot be parsed" do
    assert_raise TokenMissingError, fn -> generate("defmodule Broken do") end
  end
end
