defmodule Muta.Suite do
  alias Muta.UntrustworthyError

  @enforce_keys [:modules, :test_ids]
  defstruct [:modules, :test_ids]

  @type t :: %__MODULE__{modules: [module()], test_ids: MapSet.t({module(), atom()})}

  @spec load([Path.t()]) :: t()
  def load(files) do
    modules = Enum.flat_map(files, &defined_in/1)

    %__MODULE__{modules: modules, test_ids: test_ids(modules)}
  end

  defp defined_in(file) do
    case Code.require_file(file) do
      nil -> refuse_already_loaded(file)
      compiled -> compiled |> exunit_modules() |> ensure_any_tests(file)
    end
  end

  defp exunit_modules(compiled) do
    for {module, _binary} <- compiled, function_exported?(module, :__ex_unit__, 0), do: module
  end

  defp ensure_any_tests([], file) do
    raise UntrustworthyError,
          "#{file} defines no ExUnit tests. Every mutant is judged only by the tests you " <>
            "name, so judging them by a file with no tests in it would report every mutant " <>
            "as surviving without running anything, which is indistinguishable from a real " <>
            "result."
  end

  defp ensure_any_tests(modules, _file), do: modules

  defp refuse_already_loaded(file) do
    raise UntrustworthyError,
          "#{file} was already loaded, so muta cannot tell which test modules it defines. " <>
            "Pass each test file once, and do not pass a file that test_helper.exs already " <>
            "requires."
  end

  defp test_ids(modules) do
    modules
    |> Enum.flat_map(& &1.__ex_unit__().tests)
    |> Enum.map(&{&1.module, &1.name})
    |> ensure_something_to_judge_by()
  end

  defp ensure_something_to_judge_by([]) do
    raise UntrustworthyError,
          "no tests were given to judge these mutants by. Every mutant would be reported " <>
            "as surviving without a single test having run, which reads exactly like a " <>
            "codebase with no tests at all."
  end

  defp ensure_something_to_judge_by(ids), do: MapSet.new(ids)
end
