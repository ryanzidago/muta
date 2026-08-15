defmodule Muta.Settings do
  @borrowed [:formatters, :max_failures, :only_test_ids, :timeout]

  @spec restored_after((-> result)) :: result when result: var
  def restored_after(work) do
    exunit = Enum.map(@borrowed, &{&1, ExUnit.configuration()[&1]})
    conflicts_allowed = Code.get_compiler_option(:ignore_module_conflict)

    try do
      work.()
    after
      ExUnit.configure(exunit)
      Code.put_compiler_option(:ignore_module_conflict, conflicts_allowed)
    end
  end
end
