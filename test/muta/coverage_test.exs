defmodule Muta.CoverageTest do
  use ExUnit.Case, async: false

  alias Muta.Coverage
  alias Muta.Support.Bands

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    :ok
  end

  defp compile_suite(source) do
    [{test_module, _binary} | _rest] = Code.compile_string(source)
    test_module
  end

  test "records which test touched which line" do
    banding =
      compile_suite(~S"""
      defmodule BandingOnlyTest do
        use ExUnit.Case, async: false

        test "bands a low number" do
          assert Muta.Support.Bands.band(50) == :low
        end
      end
      """)

    coverage = Coverage.build([Bands], [banding])

    covered = for {{Bands, signature}, _ids} <- coverage, do: signature

    assert {:band, 1} in covered
    refute {:surcharge, 1} in covered
  end

  test "separates the tests covering one function from another" do
    suite =
      compile_suite(~S"""
      defmodule SplitCoverageTest do
        use ExUnit.Case, async: false

        test "touches only banding" do
          assert Muta.Support.Bands.band(50) == :low
        end

        test "touches only surcharge" do
          assert Muta.Support.Bands.surcharge(900) == :levied
        end
      end
      """)

    coverage = Coverage.build([Bands], [suite])

    assert Coverage.tests_covering(coverage, [Bands], {:band, 1}) == [
             {SplitCoverageTest, :"test touches only banding"}
           ]

    assert Coverage.tests_covering(coverage, [Bands], {:surcharge, 1}) == [
             {SplitCoverageTest, :"test touches only surcharge"}
           ]
  end

  test "reports no tests for a line nothing exercises" do
    suite =
      compile_suite(~S"""
      defmodule NothingCoveredTest do
        use ExUnit.Case, async: false

        test "touches nothing in the target" do
          assert 1 + 1 == 2
        end
      end
      """)

    coverage = Coverage.build([Bands], [suite])

    assert Coverage.tests_covering(coverage, [Bands], {:band, 1}) == []
  end

  test "leaves the target module callable afterwards" do
    suite =
      compile_suite(~S"""
      defmodule RestoresTargetTest do
        use ExUnit.Case, async: false

        test "bands a low number" do
          assert Muta.Support.Bands.band(50) == :low
        end
      end
      """)

    Coverage.build([Bands], [suite])

    assert Bands.band(50) == :low
    assert Bands.surcharge(900) == :levied
  end
end
