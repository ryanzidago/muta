defmodule Muta.OriginalTest do
  use ExUnit.Case, async: false

  alias Muta.Original
  alias Muta.Source
  alias Muta.UntrustworthyError

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)

    :ok
  end

  test "recompiles against an absolute path, the way mix compiled the module" do
    source =
      Source.parse(
        ~S"""
        defmodule DirBound do
          def dir, do: __DIR__
        end
        """,
        "lib/nested/dir_bound.ex"
      )

    assert %Original{modules: [{module, _binary}]} = Original.compile(source)
    assert Path.type(module.dir()) == :absolute
  end

  test "leaves the file it reports alone, so findings stay readable" do
    source =
      Source.parse(
        ~S"""
        defmodule ReadableFile do
          def gate(n), do: n > 5
        end
        """,
        "lib/nested/readable_file.ex"
      )

    assert Original.compile(source).source.file == "lib/nested/readable_file.ex"
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
