defmodule Voria2.Network.FaultScheduler do
  @moduledoc """
  Periodic GenServer that checks for stale stations and webcams and creates
  auto-offline faults when they exceed the staleness threshold.

  Configured via:
    config :voria2, fault_staleness_threshold_s: 900      # 15 minutes
    config :voria2, fault_check_interval_ms: 60_000       # 1 minute
  """

  use GenServer
  require Logger
  require Ash.Query

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    interval = Application.get_env(:voria2, :fault_check_interval_ms, 60_000)
    threshold = Application.get_env(:voria2, :fault_staleness_threshold_s, 900)
    :timer.send_interval(interval, :check_staleness)
    {:ok, %{threshold: threshold}}
  end

  @impl true
  def handle_info(:check_staleness, state) do
    check_stations(state.threshold)
    check_webcams(state.threshold)
    {:noreply, state}
  end

  @doc "Check all active stations for staleness. Public for testing."
  def check_stations(threshold_s) do
    cutoff = DateTime.add(DateTime.utc_now(), -threshold_s, :second)

    stations =
      Voria2.Network.Station
      |> Ash.Query.filter(is_active == true)
      |> Ash.read!(authorize?: false)

    Enum.each(stations, fn station ->
      if station_stale?(station, cutoff) do
        maybe_create_station_fault(station)
      end
    end)
  end

  @doc "Check all active webcams for staleness. Public for testing."
  def check_webcams(threshold_s) do
    cutoff = DateTime.add(DateTime.utc_now(), -threshold_s, :second)

    webcams =
      Voria2.Network.Webcam
      |> Ash.Query.filter(is_active == true)
      |> Ash.read!(authorize?: false)

    Enum.each(webcams, fn webcam ->
      if webcam_stale?(webcam, cutoff) do
        maybe_create_webcam_fault(webcam)
      end
    end)
  end

  # ─── Staleness detection ───────────────────────────────────────────────

  defp station_stale?(station, cutoff) do
    case Voria2.Cache.station_last_seen(station.id) do
      nil -> db_station_stale?(station.id, cutoff)
      last_seen -> DateTime.compare(last_seen, cutoff) == :lt
    end
  end

  defp webcam_stale?(webcam, cutoff) do
    case Voria2.Cache.webcam_last_seen(webcam.id) do
      nil -> db_webcam_stale?(webcam.id, cutoff)
      last_seen -> DateTime.compare(last_seen, cutoff) == :lt
    end
  end

  # DB fallback: used on cold start when no ETS heartbeat exists.
  defp db_station_stale?(station_id, cutoff) do
    sensors = active_sensors_for_station(station_id)

    # Stations with no active sensors are not faulted (nothing to report)
    if Enum.empty?(sensors) do
      false
    else
      not Enum.any?(sensors, fn sensor ->
        has_recent_measurement?(sensor, cutoff)
      end)
    end
  end

  defp active_sensors_for_station(station_id) do
    Voria2.Measurements.SensorInstallation
    |> Ash.Query.filter(station_id == ^station_id)
    |> Ash.Query.load(:measurement_type)
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&is_nil(&1.removed_at))
  end

  defp has_recent_measurement?(sensor, cutoff) do
    table_module = measurement_module(sensor.measurement_type.storage_type)

    if table_module do
      sensor.id
      |> measurement_since(table_module, cutoff)
      |> Enum.any?()
    else
      false
    end
  end

  defp measurement_since(sensor_id, module, cutoff) do
    module
    |> Ash.Query.filter(sensor_installation_id == ^sensor_id and measured_at > ^cutoff)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
  end

  defp measurement_module(:scalar), do: Voria2.Measurements.TemperatureMeasurement
  defp measurement_module(:wind), do: Voria2.Measurements.WindMeasurement
  defp measurement_module(:rain), do: Voria2.Measurements.RainMeasurement
  defp measurement_module(:custom), do: Voria2.Measurements.CustomMeasurement
  defp measurement_module(_), do: nil

  defp db_webcam_stale?(webcam_id, cutoff) do
    case Voria2.Network.latest_webcam_shot(webcam_id, authorize?: false) do
      {:ok, [shot | _]} -> DateTime.compare(shot.captured_at, cutoff) == :lt
      {:ok, []} -> true
      _ -> true
    end
  end

  # ─── Fault creation ────────────────────────────────────────────────────

  defp maybe_create_station_fault(station) do
    case Voria2.Network.active_auto_fault_for_station(station.id, authorize?: false) do
      {:ok, []} ->
        Voria2.Network.detect_offline_fault!(
          %{station_id: station.id, detected_at: DateTime.utc_now()},
          authorize?: false
        )

        Logger.info("[FaultScheduler] Auto-offline fault created for station #{station.id}")

      {:ok, _existing} ->
        :already_faulted

      {:error, reason} ->
        Logger.error(
          "[FaultScheduler] Failed to check faults for station #{station.id}: #{inspect(reason)}"
        )
    end
  end

  defp maybe_create_webcam_fault(webcam) do
    case Voria2.Network.active_auto_fault_for_webcam(webcam.id, authorize?: false) do
      {:ok, []} ->
        Voria2.Network.detect_offline_fault!(
          %{webcam_id: webcam.id, detected_at: DateTime.utc_now()},
          authorize?: false
        )

        Logger.info("[FaultScheduler] Auto-offline fault created for webcam #{webcam.id}")

      {:ok, _existing} ->
        :already_faulted

      {:error, reason} ->
        Logger.error(
          "[FaultScheduler] Failed to check faults for webcam #{webcam.id}: #{inspect(reason)}"
        )
    end
  end
end
