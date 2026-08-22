defmodule Muta.Support.StrictMacro do
  defmacro must_be_ok(tag) do
    ensure_ok(tag)
  end

  defp ensure_ok(:ok), do: :ok

  defp ensure_ok(other) do
    raise ArgumentError, "must_be_ok expects :ok, got #{inspect(other)}"
  end
end
