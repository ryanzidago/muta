defmodule Muta.Mutator.LogicalTest do
  use ExUnit.Case, async: true

  alias Muta.Mutator.Logical

  defp mutate(node), do: Enum.map(Logical.mutations(node), &Macro.to_string/1)

  test "loosens an and into an or" do
    assert mutate(quote(do: member? and paid?)) == ["member? or paid?"]
  end

  test "tightens an or into an and" do
    assert mutate(quote(do: member? or paid?)) == ["member? and paid?"]
  end

  test "loosens a short-circuiting and" do
    assert mutate(quote(do: member? && paid?)) == ["member? || paid?"]
  end

  test "tightens a short-circuiting or" do
    assert mutate(quote(do: member? || paid?)) == ["member? && paid?"]
  end

  test "drops a word negation" do
    assert mutate(quote(do: not is_nil(email))) == ["is_nil(email)"]
  end

  test "drops a symbol negation" do
    assert mutate(quote(do: !expired?)) == ["expired?"]
  end

  test "leaves a negated membership test to the membership mutator" do
    assert mutate(quote(do: role not in [:owner])) == []
  end

  test "leaves a comparison alone" do
    assert mutate(quote(do: cents > 100)) == []
  end

  test "leaves arithmetic alone" do
    assert mutate(quote(do: a + b)) == []
  end

  test "leaves a bare literal alone" do
    assert mutate(quote(do: true)) == []
  end
end
