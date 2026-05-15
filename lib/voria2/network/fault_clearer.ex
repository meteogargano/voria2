defmodule Voria2.Network.FaultClearer do
  @moduledoc "Clears active auto-offline faults when hardware comes back online."

  require Logger

  def clear_station(station_id) do
    Task.Supervisor.start_child(Voria2.TaskSupervisor, fn ->
      _ = safe_run(fn -> clear_station_sync(station_id) end)
      :ok
    end)
  end

  def clear_webcam(webcam_id) do
    Task.Supervisor.start_child(Voria2.TaskSupervisor, fn ->
      _ = safe_run(fn -> clear_webcam_sync(webcam_id) end)
      :ok
    end)
  end

  def clear_station_sync(station_id) do
    case Voria2.Network.active_auto_fault_for_station(station_id, authorize?: false) do
      {:ok, [fault | _]} ->
        Voria2.Network.resolve_fault(fault, %{resolved_by_id: nil}, authorize?: false)

      {:ok, []} ->
        :ok

      _ ->
        :ok
    end
  end

  def clear_webcam_sync(webcam_id) do
    case Voria2.Network.active_auto_fault_for_webcam(webcam_id, authorize?: false) do
      {:ok, [fault | _]} ->
        Voria2.Network.resolve_fault(fault, %{resolved_by_id: nil}, authorize?: false)

      {:ok, []} ->
        :ok

      _ ->
        :ok
    end
  end

  defp safe_run(fun) do
    try do
      fun.()
    rescue
      error ->
        Logger.debug("Fault clearer failed: #{Exception.message(error)}")
        :ok
    catch
      :exit, reason ->
        Logger.debug("Fault clearer exited: #{inspect(reason)}")
        :ok

      kind, reason ->
        Logger.debug("Fault clearer #{kind}: #{inspect(reason)}")
        :ok
    end
  end
end
