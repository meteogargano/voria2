defmodule Voria2.Measurements.MeasurementType.Changes.PreventSystemUnitChange do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :unit) && is_nil(changeset.data.user_id) do
      Ash.Changeset.add_error(changeset,
        field: :unit,
        message: "cannot be changed for system measurement types"
      )
    else
      changeset
    end
  end
end
