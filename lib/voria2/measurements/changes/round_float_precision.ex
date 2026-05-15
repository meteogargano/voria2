defmodule Voria2.Measurements.Changes.RoundFloatPrecision do
  @moduledoc """
  Rounds the `value` attribute to 2 decimal places before saving.

  Used for measurements with a single float value attribute.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.Changeset.fetch_change(changeset, :value) do
        {:ok, value} when is_number(value) ->
          Ash.Changeset.change_attribute(changeset, :value, Float.round(value, 2))

        _ ->
          changeset
      end
    end)
  end
end

defmodule Voria2.Measurements.Changes.RoundFloatPrecisionWind do
  @moduledoc """
  Rounds wind float attributes (`u`, `v`, `gust`) to 2 decimal places before saving.

  Used for wind measurements.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      attrs = [:u, :v, :gust]

      Enum.reduce(attrs, changeset, fn attribute, acc ->
        case Ash.Changeset.fetch_change(changeset, attribute) do
          {:ok, value} when is_number(value) ->
            Ash.Changeset.change_attribute(acc, attribute, Float.round(value, 2))

          _ ->
            acc
        end
      end)
    end)
  end
end

defmodule Voria2.Measurements.Changes.RoundFloatPrecisionRain do
  @moduledoc """
  Rounds the `interval_mm` attribute to 2 decimal places before saving.

  Used for rain measurements.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.Changeset.fetch_change(changeset, :interval_mm) do
        {:ok, value} when is_number(value) ->
          Ash.Changeset.change_attribute(changeset, :interval_mm, Float.round(value, 2))

        _ ->
          changeset
      end
    end)
  end
end
