defmodule Voria2.Network.Fault do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Network,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "faults"
    repo Voria2.Repo

    references do
      reference :station, on_delete: :delete
      reference :webcam, on_delete: :delete
      reference :sensor_installation, on_delete: :delete
    end

    custom_indexes do
      index [:station_id, :resolved_at],
        where: "station_id IS NOT NULL",
        name: "faults_station_id_resolved_at_idx"

      index [:webcam_id, :resolved_at],
        where: "webcam_id IS NOT NULL",
        name: "faults_webcam_id_resolved_at_idx"

      index [:sensor_installation_id, :resolved_at],
        where: "sensor_installation_id IS NOT NULL",
        name: "faults_sensor_installation_id_resolved_at_idx"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :detect_offline do
      accept [:station_id, :webcam_id, :sensor_installation_id, :detected_at]
      change set_attribute(:fault_type, :auto_offline)
      change set_attribute(:reason, "offline")
    end

    create :report_manual do
      accept [:station_id, :webcam_id, :sensor_installation_id, :reason, :detected_at]
      change set_attribute(:fault_type, :manual)
    end

    update :resolve do
      accept []
      require_atomic? false
      argument :resolved_by_id, :uuid

      validate fn changeset, _ ->
        if is_nil(changeset.data.resolved_at) do
          :ok
        else
          {:error, field: :resolved_at, message: "fault is already resolved"}
        end
      end

      change fn changeset, _ ->
        resolved_by = Ash.Changeset.get_argument(changeset, :resolved_by_id)

        changeset
        |> Ash.Changeset.force_change_attribute(:resolved_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:resolved_by_id, resolved_by)
      end
    end

    read :active_for_station do
      argument :station_id, :uuid, allow_nil?: false
      filter expr(station_id == ^arg(:station_id) and is_nil(resolved_at))
      prepare build(sort: [detected_at: :desc])
    end

    read :active_for_webcam do
      argument :webcam_id, :uuid, allow_nil?: false
      filter expr(webcam_id == ^arg(:webcam_id) and is_nil(resolved_at))
      prepare build(sort: [detected_at: :desc])
    end

    read :active_for_sensor_installation do
      argument :sensor_installation_id, :uuid, allow_nil?: false
      filter expr(sensor_installation_id == ^arg(:sensor_installation_id) and is_nil(resolved_at))
      prepare build(sort: [detected_at: :desc])
    end

    read :history_for_station do
      argument :station_id, :uuid, allow_nil?: false
      filter expr(station_id == ^arg(:station_id))
      prepare build(sort: [detected_at: :desc])
    end

    read :history_for_webcam do
      argument :webcam_id, :uuid, allow_nil?: false
      filter expr(webcam_id == ^arg(:webcam_id))
      prepare build(sort: [detected_at: :desc])
    end

    read :history_for_sensor_installation do
      argument :sensor_installation_id, :uuid, allow_nil?: false
      filter expr(sensor_installation_id == ^arg(:sensor_installation_id))
      prepare build(sort: [detected_at: :desc])
    end

    read :active_for_sensor_list do
      argument :sensor_installation_ids, {:array, :uuid}, allow_nil?: false

      filter expr(
               sensor_installation_id in ^arg(:sensor_installation_ids) and is_nil(resolved_at)
             )

      prepare build(sort: [detected_at: :desc])
    end

    read :history_for_sensor_list do
      argument :sensor_installation_ids, {:array, :uuid}, allow_nil?: false
      filter expr(sensor_installation_id in ^arg(:sensor_installation_ids))
      prepare build(sort: [detected_at: :desc])
    end

    read :active_auto_for_station do
      argument :station_id, :uuid, allow_nil?: false

      filter expr(
               station_id == ^arg(:station_id) and is_nil(resolved_at) and
                 fault_type == :auto_offline
             )

      prepare build(limit: 1, sort: [detected_at: :desc])
    end

    read :active_auto_for_webcam do
      argument :webcam_id, :uuid, allow_nil?: false

      filter expr(
               webcam_id == ^arg(:webcam_id) and is_nil(resolved_at) and
                 fault_type == :auto_offline
             )

      prepare build(limit: 1, sort: [detected_at: :desc])
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:report_manual) do
      forbid_if always()
    end

    policy action(:detect_offline) do
      forbid_if always()
    end

    policy action(:resolve) do
      forbid_if always()
    end

    policy action_type(:destroy) do
      forbid_if always()
    end
  end

  validations do
    validate fn changeset, _ ->
               s = Ash.Changeset.get_attribute(changeset, :station_id)
               w = Ash.Changeset.get_attribute(changeset, :webcam_id)
               si = Ash.Changeset.get_attribute(changeset, :sensor_installation_id)
               count = Enum.count([s, w, si], &(not is_nil(&1)))

               if count == 1 do
                 :ok
               else
                 {:error,
                  field: :station_id,
                  message:
                    "exactly one subject (station, webcam, or sensor_installation) must be set"}
               end
             end,
             on: [:create]
  end

  attributes do
    uuid_primary_key :id

    attribute :fault_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:auto_offline, :manual]
    end

    attribute :reason, :string do
      allow_nil? false
      public? true
    end

    attribute :detected_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :resolved_at, :utc_datetime_usec do
      public? true
    end

    attribute :resolved_by_id, :uuid do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :station, Voria2.Network.Station do
      allow_nil? true
      public? true
    end

    belongs_to :webcam, Voria2.Network.Webcam do
      allow_nil? true
      public? true
    end

    belongs_to :sensor_installation, Voria2.Measurements.SensorInstallation do
      allow_nil? true
      public? true
    end
  end
end
