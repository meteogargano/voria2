defmodule Voria2.Measurements.RainMeasurement.Changes.ComputeIntervalFromCumulative do
  @moduledoc """
  Computes interval_mm from a cumulative sensor reading.

  Fetches the previous cumulative value from `rain_cumulative_state`, computes
  the difference, handles sensor resets (diff < 0) by storing 0.0, and updates
  the state table.
  """

  use Ash.Resource.Change

  require Ash.Query
  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      sensor_id = Ash.Changeset.get_attribute(changeset, :sensor_installation_id)
      measured_at = Ash.Changeset.get_attribute(changeset, :measured_at)
      new_cumulative = Ash.Changeset.get_argument(changeset, :cumulative_value)

      Logger.warning(
        "[CumulativeRain] sensor=#{sensor_id} new_cumulative=#{inspect(new_cumulative)} pid=#{inspect(self())}"
      )

      case existing_measurement(sensor_id, measured_at) do
        {:ok, existing} when not is_nil(existing) ->
          Logger.warning(
            "[CumulativeRain] sensor=#{sensor_id} measured_at=#{measured_at} duplicate replay -> interval=#{existing.interval_mm}"
          )

          Ash.Changeset.force_change_attribute(changeset, :interval_mm, existing.interval_mm)

        {:error, reason} ->
          Logger.error(
            "[CumulativeRain] sensor=#{sensor_id} duplicate check error: #{inspect(reason)}"
          )

          compute_interval_and_update_state(changeset, sensor_id, new_cumulative)

        _ ->
          compute_interval_and_update_state(changeset, sensor_id, new_cumulative)
      end
    end)
  end

  defp compute_interval_and_update_state(changeset, sensor_id, new_cumulative) do
    if is_nil(new_cumulative) or new_cumulative <= 0.0 do
      Logger.warning(
        "[CumulativeRain] sensor=#{sensor_id} SKIPPING state update (cumulative=#{inspect(new_cumulative)})"
      )

      Ash.Changeset.force_change_attribute(changeset, :interval_mm, 0.0)
    else
      interval_mm =
        case Voria2.Measurements.get_rain_cumulative_state(sensor_id,
               authorize?: false,
               not_found_error?: false
             ) do
          {:ok, nil} ->
            Logger.warning(
              "[CumulativeRain] sensor=#{sensor_id} state=nil -> interval=0.0 (baseline)"
            )

            0.0

          {:ok, state} ->
            diff = new_cumulative - state.last_cumulative_value
            result = max(diff, 0.0)

            Logger.warning(
              "[CumulativeRain] sensor=#{sensor_id} state=#{state.last_cumulative_value} diff=#{diff} interval=#{result}"
            )

            result

          {:error, reason} ->
            Logger.error(
              "[CumulativeRain] sensor=#{sensor_id} state fetch error: #{inspect(reason)}"
            )

            0.0
        end

      Voria2.Measurements.upsert_rain_cumulative_state!(
        %{
          sensor_installation_id: sensor_id,
          last_cumulative_value: new_cumulative,
          last_updated_at: DateTime.utc_now()
        },
        authorize?: false
      )

      Logger.warning("[CumulativeRain] sensor=#{sensor_id} state upserted to #{new_cumulative}")

      Ash.Changeset.force_change_attribute(changeset, :interval_mm, interval_mm)
    end
  end

  defp existing_measurement(sensor_id, measured_at) do
    Voria2.Measurements.RainMeasurement
    |> Ash.Query.filter(sensor_installation_id == ^sensor_id and measured_at == ^measured_at)
    |> Ash.read_one(authorize?: false)
  end
end
