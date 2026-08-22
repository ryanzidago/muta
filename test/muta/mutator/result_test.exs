defmodule Muta.Mutator.ResultTest do
  use ExUnit.Case, async: true

  alias Muta.Mutator.Result
  alias Muta.Source

  defp mutate(code) do
    {_ast, mutated} =
      code
      |> Source.parse("example.ex")
      |> Map.fetch!(:ast)
      |> Macro.prewalk([], fn node, acc ->
        {node, acc ++ Enum.map(Result.mutations(node), &Macro.to_string/1)}
      end)

    mutated
  end

  test "turns a success tag into a failure tag" do
    assert mutate("{:ok, id}") == [":error"]
  end

  test "turns a failure tag into a success tag" do
    assert mutate("{:error, :missing}") == [":ok"]
  end

  test "reaches a tag returned on its own" do
    assert mutate("def ping, do: :ok") == [":error"]
  end

  test "reaches a tag matched in a pattern" do
    assert mutate("case r do\n  {:ok, v} -> v\nend") == [":error"]
  end

  test "leaves any other atom alone" do
    assert mutate("{:pending, id}") == []
  end

  test "leaves a comparison alone" do
    assert mutate("cents > 100") == []
  end

  test "leaves a number alone" do
    assert mutate("100") == []
  end
end
