defmodule Voria2.Measurements.RainMeasurement.Changes.ComputeIntervalFromCumulative do
  @moduledoc """
  Computes interval_mm from a cumulative sensor reading.

  Fetches the previous cumulative value from `rain_cumulative_state`, computes
  the difference, handles sensor resets (diff < 0) by storing 0.0, and updates
  the state table.
  """

  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      sensor_id = Ash.Changeset.get_attribute(changeset, :sensor_installation_id)
      new_cumulative = Ash.Changeset.get_argument(changeset, :cumulative_value)

      Logger.warning(
        "[CumulativeRain] sensor=#{sensor_id} new_cumulative=#{inspect(new_cumulative)} pid=#{inspect(self())}"
      )

      # If the incoming cumulative value is 0 or negative, it is either a sensor
      # glitch (e.g. WeatherLink returning data from the wrong sensor index)
      # or a real sensor reset. In both cases we record interval=0 but do NOT
      # update the cumulative state so that the existing baseline is preserved.
      # The next non-zero reading will compute the correct delta from the last
      # known-good value; if a real reset has occurred the delta will be
      # negative and will be clamped to 0 by the existing logic.
      if is_nil(new_cumulative) or new_cumulative <= 0.0 do
        Logger.warning(
          "[CumulativeRain] sensor=#{sensor_id} SKIPPING state update (cumulative=#{inspect(new_cumulative)})"
        )

        Ash.Changeset.change_attribute(changeset, :interval_mm, 0.0)
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

        Ash.Changeset.change_attribute(changeset, :interval_mm, interval_mm)
      end
    end)
  end
end
