defmodule Muta.Support.Bands do
  def band(n) when n < 100, do: :low
  def band(_n), do: :high

  def surcharge(n) when n > 500, do: :levied
  def surcharge(_n), do: :none
end
