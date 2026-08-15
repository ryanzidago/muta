defmodule Muta.Mutator.ComparisonTest do
  use ExUnit.Case, async: true

  alias Muta.Mutator.Comparison

  defp mutate(node), do: Enum.map(Comparison.mutations(node), &Macro.to_string/1)

  test "offers the boundary and the inverse for a less-than" do
    assert mutate(quote(do: cents < 0)) == ["cents <= 0", "cents > 0"]
  end

  test "offers the boundary and the inverse for a greater-than-or-equal" do
    assert mutate(quote(do: total >= limit)) == ["total > limit", "total <= limit"]
  end

  test "offers the negation for an equality" do
    assert mutate(quote(do: status == :ok)) == ["status != :ok"]
  end

  test "offers the negation for a strict equality" do
    assert mutate(quote(do: value === nil)) == ["value !== nil"]
  end

  test "leaves arithmetic alone" do
    assert mutate(quote(do: a + b)) == []
  end

  test "leaves a function call alone" do
    assert mutate(quote(do: div(cents, 100))) == []
  end

  test "leaves a bare literal alone" do
    assert mutate(quote(do: 100)) == []
  end

  test "leaves a unary operator alone" do
    assert mutate(quote(do: -cents)) == []
  end
end
