defmodule Muta.Mutator.ConditionTest do
  use ExUnit.Case, async: true

  alias Muta.Mutator.Condition

  defp mutate(node), do: Enum.map(Condition.mutations(node), &Macro.to_string/1)

  test "forces an if down each of its branches in turn" do
    assert mutate(quote(do: if(admin?, do: :all, else: :own))) == [
             "if true do\n  :all\nelse\n  :own\nend",
             "if false do\n  :all\nelse\n  :own\nend"
           ]
  end

  test "forces an if that has no else branch" do
    assert mutate(quote(do: if(ready?, do: :go))) == [
             "if true do\n  :go\nend",
             "if false do\n  :go\nend"
           ]
  end

  test "forces an unless the same way" do
    assert mutate(quote(do: unless(blocked?, do: :go))) == [
             "unless true do\n  :go\nend",
             "unless false do\n  :go\nend"
           ]
  end

  test "leaves a comparison alone" do
    assert mutate(quote(do: cents > 100)) == []
  end

  test "leaves a case alone" do
    assert mutate(quote(do: case(x, do: (_ -> :ok)))) == []
  end

  test "leaves a bare literal alone" do
    assert mutate(quote(do: true)) == []
  end
end
