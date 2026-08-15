defmodule Muta.Verdict do
  alias Muta.Mutant
  alias Muta.Plan

  @enforce_keys [:plan, :outcome, :duration_ms]
  defstruct [:plan, :outcome, :duration_ms]

  @type t :: %__MODULE__{
          plan: Plan.t(),
          outcome: Mutant.outcome(),
          duration_ms: non_neg_integer()
        }

  @spec followed_by(t(), t()) :: t()
  def followed_by(%__MODULE__{} = verdict, %__MODULE__{} = later) do
    %__MODULE__{
      verdict
      | outcome: later.outcome,
        duration_ms: verdict.duration_ms + later.duration_ms
    }
  end

  @spec mutant(t()) :: Mutant.t()
  def mutant(%__MODULE__{} = verdict) do
    Mutant.evaluated(verdict.plan.mutation, verdict.outcome, verdict.duration_ms)
  end
end
