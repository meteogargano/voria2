defmodule Voria2.Measurements.SensorInstallation.Changes.InvalidateCache do
  use Ash.Resource.Change

  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      case Ash.get(Voria2.Measurements.MeasurementType, record.measurement_type_id,
             authorize?: false
           ) do
        {:ok, mt} -> Voria2.Cache.invalidate_sensor(record.station_id, mt.slug)
        _ -> :ok
      end

      {:ok, record}
    end)
  end
end
