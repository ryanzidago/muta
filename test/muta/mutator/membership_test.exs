defmodule Muta.Mutator.MembershipTest do
  use ExUnit.Case, async: true

  alias Muta.Mutator.Membership

  defp mutate(node), do: Enum.map(Membership.mutations(node), &Macro.to_string/1)

  test "excludes what the source includes" do
    assert mutate(quote(do: role in [:owner, :admin])) == ["role not in [:owner, :admin]"]
  end

  test "reaches the membership test inside a negation, where the whole node is not its own" do
    assert mutate(quote(do: role not in [:owner])) == []
  end

  test "leaves a comparison alone" do
    assert mutate(quote(do: cents > 100)) == []
  end

  test "leaves a bare literal alone" do
    assert mutate(quote(do: :owner)) == []
  end
end
