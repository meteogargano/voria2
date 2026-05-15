defmodule Voria2.Network do
  use Ash.Domain, otp_app: :voria2

  require Ash.Query

  resources do
    resource Voria2.Network.Installation do
      define :create_installation, action: :create
      define :list_installations, action: :read
      define :get_installation, action: :read, get_by: [:id]
      define :update_installation, action: :update
      define :destroy_installation, action: :destroy
      define :add_installation_picture, action: :add_picture, args: [:picture_key]
      define :remove_installation_picture, action: :remove_picture, args: [:picture_key]
    end

    resource Voria2.Network.Station do
      define :create_station, action: :create
      define :list_stations, action: :read
      define :get_station, action: :read, get_by: [:id]
      define :get_station_by_slug, action: :read, get_by: [:slug]
      define :update_station, action: :update
      define :destroy_station, action: :destroy
    end

    resource Voria2.Network.Webcam do
      define :create_webcam, action: :create
      define :list_webcams, action: :read
      define :get_webcam, action: :read, get_by: [:id]
      define :get_webcam_by_slug, action: :read, get_by: [:slug]
      define :update_webcam, action: :update
      define :destroy_webcam, action: :destroy
    end

    resource Voria2.Network.WebcamShot do
      define :record_webcam_shot, action: :record
      define :list_webcam_shots, action: :read
      define :latest_webcam_shot, action: :latest_for_webcam, args: [:webcam_id]
      define :webcam_shot_history, action: :history, args: [:webcam_id, :from, :to]
      define :destroy_webcam_shot, action: :destroy
      define :get_webcam_shot_by_hash, action: :by_hash, args: [:hash]
    end

    resource Voria2.Network.StationApiKey do
      define :generate_station_api_key, action: :generate, args: [:station_id]
      define :revoke_station_api_key, action: :revoke
      define :list_station_api_keys, action: :read
      define :get_station_api_key_by_key, action: :by_key, args: [:key]
    end

    resource Voria2.Network.WebcamApiKey do
      define :generate_webcam_api_key, action: :generate, args: [:webcam_id]
      define :revoke_webcam_api_key, action: :revoke
      define :list_webcam_api_keys, action: :read
      define :get_webcam_api_key_by_key, action: :by_key, args: [:key]
    end

    resource Voria2.Network.Fault do
      define :detect_offline_fault, action: :detect_offline
      define :report_manual_fault, action: :report_manual
      define :resolve_fault, action: :resolve
      define :list_faults, action: :read
      define :get_fault, action: :read, get_by: [:id]
      define :active_faults_for_station, action: :active_for_station, args: [:station_id]
      define :active_faults_for_webcam, action: :active_for_webcam, args: [:webcam_id]

      define :active_faults_for_sensor,
        action: :active_for_sensor_installation,
        args: [:sensor_installation_id]

      define :fault_history_for_station, action: :history_for_station, args: [:station_id]
      define :fault_history_for_webcam, action: :history_for_webcam, args: [:webcam_id]

      define :fault_history_for_sensor,
        action: :history_for_sensor_installation,
        args: [:sensor_installation_id]

      define :active_auto_fault_for_station, action: :active_auto_for_station, args: [:station_id]
      define :active_auto_fault_for_webcam, action: :active_auto_for_webcam, args: [:webcam_id]

      define :active_faults_for_sensor_list,
        action: :active_for_sensor_list,
        args: [:sensor_installation_ids]

      define :fault_history_for_sensor_list,
        action: :history_for_sensor_list,
        args: [:sensor_installation_ids]
    end
  end

  # Generate API keys with an optional label (label field not in code interface args
  # to preserve backward-compatible callers that pass opts as second arg).
  def generate_station_api_key_labeled(station_id, label, opts) do
    Voria2.Network.StationApiKey
    |> Ash.Changeset.for_create(:generate, %{station_id: station_id, label: label})
    |> Ash.create(opts)
  end

  def generate_webcam_api_key_labeled(webcam_id, label, opts) do
    Voria2.Network.WebcamApiKey
    |> Ash.Changeset.for_create(:generate, %{webcam_id: webcam_id, label: label})
    |> Ash.create(opts)
  end

  def count_webcam_shots_in_range!([], _from, _to), do: 0

  def count_webcam_shots_in_range!(webcam_ids, from, to) when is_list(webcam_ids) do
    webcam_shot_query(webcam_ids, from, to)
    |> Ash.count!(authorize?: false)
  end

  def list_webcam_shot_batch_in_range!(webcam_ids, from, to, limit, cursor \\ nil)

  def list_webcam_shot_batch_in_range!([], _from, _to, _limit, _cursor), do: []

  def list_webcam_shot_batch_in_range!(webcam_ids, from, to, limit, cursor)
      when is_list(webcam_ids) and is_integer(limit) and limit > 0 do
    webcam_shot_query(webcam_ids, from, to)
    |> maybe_apply_webcam_shot_cursor(cursor)
    |> Ash.Query.sort(captured_at: :asc, id: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.read!(authorize?: false)
  end

  # Admin-only bulk delete: destroys shots in the given time range, cleans up R2.
  def admin_bulk_delete_shots(actor, from, to) do
    admin_bulk_delete_shots(actor, nil, from, to)
  end

  def admin_bulk_delete_shots(actor, webcam_id, from, to) do
    unless actor.admin, do: raise(Ash.Error.Forbidden, errors: [])

    query =
      Voria2.Network.WebcamShot
      |> Ash.Query.filter(captured_at >= ^from and captured_at <= ^to)

    query =
      if webcam_id do
        Ash.Query.filter(query, webcam_id == ^webcam_id)
      else
        query
      end

    shots = Ash.read!(query, authorize?: false)
    count = length(shots)
    s3_refs = Enum.map(shots, fn s -> {s.s3_key, s.s3_bucket} end)

    Ash.bulk_destroy!(shots, :destroy, %{}, authorize?: false, return_errors?: true)

    Task.Supervisor.start_child(Voria2.TaskSupervisor, fn ->
      Enum.each(s3_refs, fn {key, bucket} -> Voria2.Storage.delete(key, bucket) end)
    end)

    {:ok, count}
  end

  def get_webcam_with_latest_shot(webcam_id) do
    with {:ok, webcam} <- get_webcam(webcam_id, authorize?: false),
         {:ok, shot} <- Voria2.Cache.latest_shot_for_webcam(webcam_id) do
      {:ok, %{webcam: webcam, latest_shot: shot}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def list_webcams_with_latest_shots do
    Voria2.Cache.all_webcams_latest_shots()
  end

  def list_webcams_with_latest_shots_and_installations do
    with {:ok, pairs} <- list_webcams_with_latest_shots(),
         {:ok, installations} <-
           Voria2.Network.Installation
           |> Ash.Query.filter(is_active == true)
           |> Ash.read(authorize?: false) do
      install_map = Map.new(installations, &{&1.id, &1})

      enriched =
        Enum.map(pairs, fn %{webcam: webcam, latest_shot: shot} ->
          %{
            webcam: webcam,
            latest_shot: shot,
            installation: Map.get(install_map, webcam.installation_id)
          }
        end)

      {:ok, enriched}
    end
  end

  def list_all_active_faults do
    Voria2.Network.Fault
    |> Ash.Query.filter(is_nil(resolved_at))
    |> Ash.read(authorize?: false)
  end

  def list_public_map_data do
    with {:ok, installations} <-
           Voria2.Network.Installation
           |> Ash.Query.filter(is_active == true)
           |> Ash.Query.load(
             stations: Ash.Query.filter(Voria2.Network.Station, is_active == true),
             webcams: Ash.Query.filter(Voria2.Network.Webcam, is_active == true)
           )
           |> Ash.read(authorize?: false),
         {:ok, faults} <- list_all_active_faults() do
      faulted_station_ids =
        faults
        |> Enum.map(& &1.station_id)
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      faulted_webcam_ids =
        faults
        |> Enum.map(& &1.webcam_id)
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      sensor_fault_station_ids =
        case Enum.filter(faults, &(!is_nil(&1.sensor_installation_id))) do
          [] ->
            MapSet.new()

          sensor_faults ->
            case Ash.load(sensor_faults, [:sensor_installation], authorize?: false) do
              {:ok, loaded} ->
                loaded
                |> Enum.map(fn f -> f.sensor_installation && f.sensor_installation.station_id end)
                |> Enum.reject(&is_nil/1)
                |> MapSet.new()

              _ ->
                MapSet.new()
            end
        end

      faulted_station_ids = MapSet.union(faulted_station_ids, sensor_fault_station_ids)

      entries =
        Enum.map(installations, fn installation ->
          first_station = List.first(installation.stations)

          has_webcam = installation.webcams != []

          has_fault =
            Enum.any?(installation.stations, &MapSet.member?(faulted_station_ids, &1.id)) or
              Enum.any?(installation.webcams, &MapSet.member?(faulted_webcam_ids, &1.id))

          %{
            installation: installation,
            first_station: first_station,
            has_webcam: has_webcam,
            has_fault: has_fault
          }
        end)

      {:ok, entries}
    end
  end

  defp webcam_shot_query(webcam_ids, from, to) do
    Voria2.Network.WebcamShot
    |> Ash.Query.filter(webcam_id in ^webcam_ids and captured_at >= ^from and captured_at <= ^to)
  end

  defp maybe_apply_webcam_shot_cursor(query, nil), do: query

  defp maybe_apply_webcam_shot_cursor(query, {captured_at, id}) do
    Ash.Query.filter(
      query,
      captured_at > ^captured_at or (captured_at == ^captured_at and id > ^id)
    )
  end
end
