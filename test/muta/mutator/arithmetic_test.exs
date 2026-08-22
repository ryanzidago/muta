defmodule Muta.Mutator.ArithmeticTest do
  use ExUnit.Case, async: true

  alias Muta.Mutator.Arithmetic

  defp mutate(node), do: Enum.map(Arithmetic.mutations(node), &Macro.to_string/1)

  test "turns an addition into a subtraction" do
    assert mutate(quote(do: subtotal + gst)) == ["subtotal - gst"]
  end

  test "turns a subtraction into an addition" do
    assert mutate(quote(do: gross - deductions)) == ["gross + deductions"]
  end

  test "turns a multiplication into a division" do
    assert mutate(quote(do: cents * rate)) == ["cents / rate"]
  end

  test "turns a division into a multiplication" do
    assert mutate(quote(do: total / count)) == ["total * count"]
  end

  test "leaves a negation alone" do
    assert mutate(quote(do: -cents)) == []
  end

  test "leaves a comparison alone" do
    assert mutate(quote(do: cents > 100)) == []
  end

  test "leaves string concatenation alone" do
    assert mutate(quote(do: first <> last)) == []
  end

  test "leaves a bare literal alone" do
    assert mutate(quote(do: 100)) == []
  end
end
