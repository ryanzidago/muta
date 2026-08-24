defmodule Muta.Mutator.BoundaryTest do
  use ExUnit.Case, async: true

  alias Muta.Mutator.Boundary

  defp mutate(node), do: Enum.map(Boundary.mutations(node), &Macro.to_string/1)

  test "tightens a greater-than, since Comparison already loosens it" do
    assert mutate(quote(do: cents > 5000)) == ["cents > 5001"]
  end

  test "loosens a greater-than-or-equal, since Comparison already tightens it" do
    assert mutate(quote(do: age >= 18)) == ["age >= 17"]
  end

  test "tightens a less-than" do
    assert mutate(quote(do: cents < 5000)) == ["cents < 4999"]
  end

  test "loosens a less-than-or-equal" do
    assert mutate(quote(do: subtotal <= 0)) == ["subtotal <= 1"]
  end

  test "shifts the other way when the limit is written on the left" do
    assert mutate(quote(do: 5000 < cents)) == ["5001 < cents"]
  end

  test "offers both neighbours of an equality, which has no boundary to loosen" do
    assert mutate(quote(do: count == 3)) == ["count == 2", "count == 4"]
  end

  test "offers both neighbours of a strict inequality" do
    assert mutate(quote(do: count !== 3)) == ["count !== 2", "count !== 4"]
  end

  test "leaves a comparison of two variables alone" do
    assert mutate(quote(do: total >= limit)) == []
  end

  test "leaves a comparison against a module attribute alone" do
    assert mutate(quote(do: cents > @free_shipping)) == []
  end

  test "leaves a float limit alone" do
    assert mutate(quote(do: rate > 1.5)) == []
  end

  test "leaves arithmetic alone" do
    assert mutate(quote(do: a + 1)) == []
  end

  test "leaves a bare literal alone" do
    assert mutate(quote(do: 100)) == []
  end
end
