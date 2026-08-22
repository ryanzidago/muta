defmodule Muta.Changed do
  @hunk ~r/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/m

  @spec lines_since(String.t(), Path.t()) :: MapSet.t(pos_integer())
  def lines_since(ref, file) do
    ref |> diff(file) |> hunks() |> Enum.reduce(MapSet.new(), &MapSet.union(&2, &1))
  end

  @spec every_line(String.t()) :: MapSet.t(pos_integer())
  def every_line(code) do
    MapSet.new(1..max(length(String.split(code, "\n")), 1))
  end

  defp diff(ref, file) do
    options = [cd: Path.dirname(Path.expand(file)), stderr_to_stdout: true]

    case System.cmd("git", ["diff", "--unified=0", ref, "--", Path.expand(file)], options) do
      {output, 0} ->
        output

      {output, status} ->
        raise ArgumentError,
              "git diff #{ref} -- #{file} failed with status #{status}: #{String.trim(output)}. " <>
                "muta needs a ref it can diff against to scope mutation to changed lines."
    end
  end

  defp hunks(output) do
    @hunk
    |> Regex.scan(output)
    |> Enum.map(&span/1)
  end

  defp span([_match, start]), do: span([nil, start, "1"])
  defp span([_match, start, ""]), do: span([nil, start, "1"])

  defp span([_match, start, count]) do
    first = String.to_integer(start)
    MapSet.new(first..(first + String.to_integer(count) - 1)//1)
  end
end
