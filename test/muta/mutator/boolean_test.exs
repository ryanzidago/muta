defmodule Muta.Mutator.BooleanTest do
  use ExUnit.Case, async: true

  alias Muta.Mutator.Boolean
  alias Muta.Source

  defp mutate(code) do
    {_ast, mutated} =
      code
      |> Source.parse("example.ex")
      |> Map.fetch!(:ast)
      |> Macro.prewalk([], fn node, acc ->
        {node, acc ++ Enum.map(Boolean.mutations(node), &Macro.to_string/1)}
      end)

    mutated
  end

  test "turns true into false" do
    assert mutate("def bookable?, do: true") == ["false"]
  end

  test "turns false into true" do
    assert mutate("def bookable?, do: false") == ["true"]
  end

  test "reaches a boolean passed as an option" do
    assert mutate("Repo.all(q, prefix: true)") == ["false"]
  end

  test "leaves nil alone" do
    assert mutate("def missing, do: nil") == []
  end

  test "leaves a result tag alone" do
    assert mutate("{:ok, id}") == []
  end

  test "leaves a comparison alone" do
    assert mutate("cents > 100") == []
  end
end
