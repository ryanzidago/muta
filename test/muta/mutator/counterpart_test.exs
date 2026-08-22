defmodule Muta.Mutator.CounterpartTest do
  use ExUnit.Case, async: true

  alias Muta.Mutator.Counterpart

  defp mutate(node), do: Enum.map(Counterpart.mutations(node), &Macro.to_string/1)

  test "keeps what the source discards" do
    assert mutate(quote(do: Enum.filter(bookings, &open?/1))) ==
             ["Enum.reject(bookings, &open?/1)"]
  end

  test "discards what the source keeps" do
    assert mutate(quote(do: Enum.reject(bookings, &open?/1))) ==
             ["Enum.filter(bookings, &open?/1)"]
  end

  test "settles for one where the source demands all" do
    assert mutate(quote(do: Enum.all?(items, &paid?/1))) == ["Enum.any?(items, &paid?/1)"]
  end

  test "takes the other end of an ordering" do
    assert mutate(quote(do: Enum.min_by(slots, & &1.starts_at))) ==
             ["Enum.max_by(slots, & &1.starts_at)"]
  end

  test "swaps the head of a list for its tail" do
    assert mutate(quote(do: List.first(slots))) == ["List.last(slots)"]
  end

  test "looks at the wrong end of a string" do
    assert mutate(quote(do: String.starts_with?(email, "admin"))) ==
             ["String.ends_with?(email, \"admin\")"]
  end

  test "leaves a function with no counterpart alone" do
    assert mutate(quote(do: Enum.map(bookings, &fee/1))) == []
  end

  test "leaves a call on another module alone" do
    assert mutate(quote(do: Repo.all(query))) == []
  end

  test "leaves a local call alone" do
    assert mutate(quote(do: filter(bookings))) == []
  end

  test "leaves a comparison alone" do
    assert mutate(quote(do: cents > 100)) == []
  end
end
