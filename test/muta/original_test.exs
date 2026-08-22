defmodule Muta.OriginalTest do
  use ExUnit.Case, async: false

  alias Muta.Original
  alias Muta.Source
  alias Muta.UntrustworthyError

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)

    :ok
  end

  test "refuses a module that defines a guard, which its callers already expanded" do
    source =
      Source.parse(
        ~S"""
        defmodule ExpandedLimits do
          defguard over?(cents) when cents > 5000
        end
        """,
        "expanded_limits.ex"
      )

    assert_raise UntrustworthyError, ~r/defines macros/, fn -> Original.compile(source) end
  end

  test "refuses a module that defines a macro" do
    source =
      Source.parse(
        ~S"""
        defmodule ExpandedShout do
          defmacro shout(word), do: quote(do: String.upcase(unquote(word)))
        end
        """,
        "expanded_shout.ex"
      )

    assert_raise UntrustworthyError, ~r/defines macros/, fn -> Original.compile(source) end
  end

  test "accepts a module that only defines functions" do
    source =
      Source.parse(
        ~S"""
        defmodule PlainLimits do
          def over?(cents), do: cents > 5000
        end
        """,
        "plain_limits.ex"
      )

    assert %Original{modules: [{PlainLimits, _binary}]} = Original.compile(source)
  end
end
