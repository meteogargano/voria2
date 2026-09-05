defmodule Voria2.Network.WebcamShotPurger do
  use GenServer

  @name __MODULE__
  @topic "webcam_shot_purger"
  @batch_size 100
  @max_recent_errors 10

  def child_spec(opts) do
    %{
      id: @name,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Voria2.PubSub, @topic)
  end

  def snapshot do
    GenServer.call(@name, :snapshot)
  end

  def start_purge(actor, attrs) do
    GenServer.call(@name, {:start_purge, actor, attrs})
  end

  @impl true
  def init(_) do
    {:ok, idle_state()}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot_from_state(state), state}
  end

  def handle_call({:start_purge, _actor, _attrs}, _from, %{status: :running} = state) do
    {:reply, {:error, :already_running}, state}
  end

  def handle_call({:start_purge, actor, attrs}, _from, _state) do
    webcam_ids = attrs.webcam_ids
    from = attrs.from
    to = attrs.to

    total = Voria2.Network.count_webcam_shots_in_range!(webcam_ids, from, to)

    started_state = %{
      status: :running,
      job_ref: System.unique_integer([:positive]),
      actor_id: actor.id,
      webcam_ids: webcam_ids,
      from: from,
      to: to,
      total: total,
      processed: 0,
      deleted: 0,
      failed: 0,
      batches_completed: 0,
      current_batch_size: 0,
      cursor: nil,
      started_at: DateTime.utc_now(),
      finished_at: nil,
      recent_errors: []
    }

    send(self(), :process_next_batch)
    broadcast_snapshot(started_state)

    {:reply, {:ok, snapshot_from_state(started_state)}, started_state}
  end

  @impl true
  def handle_info(:process_next_batch, %{status: :running} = state) do
    batch =
      Voria2.Network.list_webcam_shot_batch_in_range!(
        state.webcam_ids,
        state.from,
        state.to,
        @batch_size,
        state.cursor
      )

    if batch == [] do
      finished_state = %{
        state
        | status: :completed,
          current_batch_size: 0,
          finished_at: DateTime.utc_now()
      }

      broadcast_snapshot(finished_state)
      {:noreply, finished_state}
    else
      {deleted_count, failed_count, recent_errors, affected_webcam_ids} =
        purge_batch(batch, state.recent_errors)

      last_shot = List.last(batch)

      Enum.each(affected_webcam_ids, &Voria2.Cache.invalidate_latest_shot/1)

      next_state = %{
        state
        | processed: state.processed + length(batch),
          deleted: state.deleted + deleted_count,
          failed: state.failed + failed_count,
          batches_completed: state.batches_completed + 1,
          current_batch_size: length(batch),
          cursor: {last_shot.captured_at, last_shot.id},
          recent_errors: recent_errors
      }

      broadcast_snapshot(next_state)
      send(self(), :process_next_batch)

      {:noreply, next_state}
    end
  rescue
    error ->
      failed_state = %{
        state
        | status: :failed,
          finished_at: DateTime.utc_now(),
          recent_errors: push_recent_error(state.recent_errors, Exception.message(error))
      }

      broadcast_snapshot(failed_state)
      {:noreply, failed_state}
  end

  def handle_info(:process_next_batch, state), do: {:noreply, state}

  defp purge_batch(batch, recent_errors) do
    Enum.reduce(batch, {0, 0, recent_errors, MapSet.new()}, fn shot,
                                                               {deleted, failed, errors,
                                                                affected_ids} ->
      affected_ids = MapSet.put(affected_ids, shot.webcam_id)

      case Voria2.Storage.delete(shot.s3_key, shot.s3_bucket) do
        :ok ->
          case Ash.destroy(shot, authorize?: false) do
            :ok ->
              {deleted + 1, failed, errors, affected_ids}

            {:error, reason} ->
              message = "#{shot.s3_key}: #{inspect(reason)}"
              {deleted, failed + 1, push_recent_error(errors, message), affected_ids}

            _other ->
              {deleted + 1, failed, errors, affected_ids}
          end

        {:error, reason} ->
          message = "#{shot.s3_key}: #{inspect(reason)}"
          {deleted, failed + 1, push_recent_error(errors, message), affected_ids}
      end
    end)
    |> then(fn {deleted, failed, errors, affected_ids} ->
      {deleted, failed, errors, MapSet.to_list(affected_ids)}
    end)
  end

  defp snapshot_from_state(state) do
    Map.take(state, [
      :status,
      :job_ref,
      :actor_id,
      :webcam_ids,
      :from,
      :to,
      :total,
      :processed,
      :deleted,
      :failed,
      :batches_completed,
      :current_batch_size,
      :cursor,
      :started_at,
      :finished_at,
      :recent_errors
    ])
  end

  defp push_recent_error(errors, error) do
    [error | errors]
    |> Enum.take(@max_recent_errors)
  end

  defp broadcast_snapshot(state) do
    Phoenix.PubSub.broadcast(
      Voria2.PubSub,
      @topic,
      {:webcam_shot_purger, snapshot_from_state(state)}
    )
  end

  defp idle_state do
    %{
      status: :idle,
      job_ref: nil,
      actor_id: nil,
      webcam_ids: [],
      from: nil,
      to: nil,
      total: 0,
      processed: 0,
      deleted: 0,
      failed: 0,
      batches_completed: 0,
      current_batch_size: 0,
      cursor: nil,
      started_at: nil,
      finished_at: nil,
      recent_errors: []
    }
  end
end
