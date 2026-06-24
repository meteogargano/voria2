defmodule Voria2.Network.FaultScheduler do
  @moduledoc """
  Periodic GenServer that checks for stale stations and webcams and creates
  auto-offline faults when they exceed the staleness threshold.

  The staleness check is batched: a single UNION query across all measurement
  hypertables determines which sensors reported recently, so the whole fleet
  is checked in ~3 queries regardless of size (instead of one query per
  sensor per station).

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
    seed_heartbeats(threshold)
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

    stations = active_stations()
    sensors_by_station = active_sensors_grouped()
    recent_sensor_ids = recent_sensor_ids(cutoff)

    Enum.each(stations, fn station ->
      if station_stale?(station, cutoff, sensors_by_station, recent_sensor_ids) do
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

  defp station_stale?(station, cutoff, sensors_by_station, recent_sensor_ids) do
    case Voria2.Cache.station_last_seen(station.id) do
      last_seen when not is_nil(last_seen) ->
        DateTime.compare(last_seen, cutoff) == :lt

      nil ->
        # Cold-heartbeat DB fallback, batched across the whole fleet.
        sensor_ids = Map.get(sensors_by_station, station.id, [])

        fresh =
          if Enum.empty?(sensor_ids) do
            # Stations with no active sensors are never faulted.
            true
          else
            Enum.any?(sensor_ids, &MapSet.member?(recent_sensor_ids, &1))
          end

        # Warm the heartbeat so subsequent ticks use the cheap ETS fast-path.
        if fresh, do: Voria2.Cache.touch_station(station.id)

        not fresh
    end
  end

  defp webcam_stale?(webcam, cutoff) do
    case Voria2.Cache.webcam_last_seen(webcam.id) do
      last_seen when not is_nil(last_seen) -> DateTime.compare(last_seen, cutoff) == :lt
      nil -> db_webcam_stale?(webcam.id, cutoff)
    end
  end

  defp db_webcam_stale?(webcam_id, cutoff) do
    case Voria2.Network.latest_webcam_shot(webcam_id, authorize?: false) do
      {:ok, [shot | _]} -> DateTime.compare(shot.captured_at, cutoff) == :lt
      {:ok, []} -> true
      _ -> true
    end
  end

  # ─── Batched data loading ──────────────────────────────────────────────

  defp active_stations do
    Voria2.Network.Station
    |> Ash.Query.filter(is_active == true)
    |> Ash.read!(authorize?: false)
  end

  # Loads every SensorInstallation once and groups active ones by station.
  # Returns %{station_id => [sensor_installation_id, ...]}.
  defp active_sensors_grouped do
    Voria2.Measurements.SensorInstallation
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&is_nil(&1.removed_at))
    |> Enum.group_by(& &1.station_id, & &1.id)
  end

  # Queries each measurement table for sensors that reported since the cutoff,
  # returning a MapSet of sensor_installation_ids. Uses Ecto.Query against the
  # Ash resource schemas so UUID/timestamp type conversion is handled correctly.
  defp recent_sensor_ids(cutoff) do
    [
      Voria2.Measurements.TemperatureMeasurement,
      Voria2.Measurements.HumidityMeasurement,
      Voria2.Measurements.PressureMeasurement,
      Voria2.Measurements.WindMeasurement,
      Voria2.Measurements.RainMeasurement,
      Voria2.Measurements.CustomMeasurement
    ]
    |> Enum.flat_map(fn module ->
      import Ecto.Query

      Voria2.Repo.all(
        from m in module,
          where: m.measured_at > ^cutoff,
          select: m.sensor_installation_id
      )
    end)
    |> MapSet.new()
  end

  # Warm ETS heartbeats from the DB so the first scheduled tick after a
  # (re)start uses the cheap ETS fast-path. Best-effort: any DB error is
  # swallowed so app boot is never blocked by it.
  defp seed_heartbeats(threshold_s) do
    cutoff = DateTime.add(DateTime.utc_now(), -threshold_s, :second)

    try do
      sensors = active_sensors_grouped()
      recent = recent_sensor_ids(cutoff)

      for {station_id, sensor_ids} <- sensors,
          Enum.any?(sensor_ids, &MapSet.member?(recent, &1)) do
        Voria2.Cache.touch_station(station_id)
      end
    catch
      kind, reason ->
        Logger.warning("[FaultScheduler] heartbeat seeding skipped (#{kind}): #{inspect(reason)}")
    end

    :ok
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
