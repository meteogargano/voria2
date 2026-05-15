defmodule Voria2.CacheInvalidationListener do
  @moduledoc """
  GenServer that listens for cache invalidation messages on the PubSub topic
  and applies them to the local ETS cache. Enables multi-node consistency.
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(Voria2.PubSub, "cache_invalidation")
    Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")
    Phoenix.PubSub.subscribe(Voria2.PubSub, "webcam_shots")
    Logger.info("Cache invalidation listener started")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:invalidate_key, api_key}, state) do
    :ets.delete(:voria2_cache, {:api_key, api_key})
    {:noreply, state}
  end

  def handle_info({:invalidate_sensor, station_id, slug}, state) do
    :ets.delete(:voria2_cache, {:sensor, station_id, slug})
    {:noreply, state}
  end

  def handle_info({:new_measurement, %{station_id: sid, summary_type: st}}, state)
      when not is_nil(st) do
    :ets.delete(:voria2_cache, {:summary, st, sid})

    with {:ok, station} <- safe_get_station(sid) do
      Voria2.Cache.invalidate_dailylog(station)

      start_safe_task(fn ->
        Voria2.Cache.warm_dailylog(station)
      end)
    end

    start_safe_task(fn ->
      Voria2.Cache.warm_summary(sid, st)
    end)

    {:noreply, state}
  end

  def handle_info({:new_measurement, %{station_id: sid, measured_at: measured_at}}, state) do
    with {:ok, station} <- safe_get_station(sid) do
      Voria2.Cache.invalidate_dailylog(station, measured_at)

      start_safe_task(fn ->
        Voria2.Cache.warm_dailylog(station, measured_at)
      end)
    end

    {:noreply, state}
  end

  def handle_info({:new_measurement, _}, state), do: {:noreply, state}

  def handle_info({:invalidate_webcam_key, key}, state) do
    :ets.delete(:voria2_cache, {:webcam_key, key})
    {:noreply, state}
  end

  def handle_info({:invalidate_latest_shot, webcam_id}, state) do
    :ets.delete(:voria2_cache, {:latest_shot, webcam_id})
    :ets.delete(:voria2_cache, {:all_webcams_latest})
    {:noreply, state}
  end

  def handle_info({:new_webcam_shot, %{webcam_id: id}}, state) do
    :ets.delete(:voria2_cache, {:latest_shot, id})
    :ets.delete(:voria2_cache, {:all_webcams_latest})

    start_safe_task(fn ->
      Voria2.Cache.warm_latest_shot(id)
      Voria2.Cache.warm_all_webcams_latest()
    end)

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp safe_get_station(station_id) do
    safe_run(
      fn -> Voria2.Network.get_station(station_id, authorize?: false) end,
      {:error, :unavailable}
    )
  end

  defp start_safe_task(fun) do
    Task.Supervisor.start_child(Voria2.TaskSupervisor, fn ->
      _ = safe_run(fun, :ok)
      :ok
    end)
  end

  defp safe_run(fun, fallback) do
    try do
      fun.()
    rescue
      error ->
        Logger.debug("Background cache task failed: #{Exception.message(error)}")
        fallback
    catch
      :exit, reason ->
        Logger.debug("Background cache task exited: #{inspect(reason)}")
        fallback

      kind, reason ->
        Logger.debug("Background cache task #{kind}: #{inspect(reason)}")
        fallback
    end
  end
end
