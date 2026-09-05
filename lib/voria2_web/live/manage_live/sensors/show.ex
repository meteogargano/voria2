defmodule Voria2Web.ManageLive.Sensors.Show do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Voria2.Measurements.get_sensor_installation(id, actor: socket.assigns.current_user) do
      {:ok, sensor} ->
        station = load_station(sensor.station_id, socket.assigns.current_user)

        installation =
          if station,
            do: load_installation(station.installation_id, socket.assigns.current_user),
            else: nil

        measurement_type =
          case sensor.measurement_type_id do
            nil ->
              nil

            mtid ->
              case Voria2.Measurements.get_measurement_type(mtid,
                     actor: socket.assigns.current_user
                   ) do
                {:ok, mt} -> mt
                _ -> nil
              end
          end

        active_faults = Voria2.Network.active_faults_for_sensor!(id)
        fault_history = Voria2.Network.fault_history_for_sensor!(id)

        {:ok,
         socket
         |> assign(:page_title, gettext("Sensor"))
         |> assign(:active_section, :installations)
         |> assign(:sensor, sensor)
         |> assign(:station, station)
         |> assign(:installation, installation)
         |> assign(:measurement_type, measurement_type)
         |> assign(:active_faults, active_faults)
         |> assign(:fault_history, fault_history)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Sensor not found."))
         |> push_navigate(to: ~p"/manage/installations")}
    end
  end

  def handle_event("decommission", _params, socket) do
    case Voria2.Measurements.decommission_sensor(
           socket.assigns.sensor,
           actor: socket.assigns.current_user
         ) do
      {:ok, sensor} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Sensor decommissioned."))
         |> assign(:sensor, sensor)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to decommission sensor."))}
    end
  end

  def handle_event("delete", _params, socket) do
    case Voria2.Measurements.destroy_sensor_installation(
           socket.assigns.sensor,
           actor: socket.assigns.current_user
         ) do
      :ok ->
        redirect_to =
          if socket.assigns.station,
            do: ~p"/manage/stations/#{socket.assigns.station.id}?tab=sensors",
            else: ~p"/manage/installations"

        {:noreply,
         socket
         |> put_flash(:info, gettext("Sensor deleted."))
         |> push_navigate(to: redirect_to)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete sensor."))}
    end
  end

  def handle_event("report_fault", %{"reason" => reason}, socket) do
    case Voria2.Network.report_manual_fault(
           %{
             sensor_installation_id: socket.assigns.sensor.id,
             reason: reason,
             detected_at: DateTime.utc_now()
           },
           actor: socket.assigns.current_user
         ) do
      {:ok, _} ->
        active_faults = Voria2.Network.active_faults_for_sensor!(socket.assigns.sensor.id)
        fault_history = Voria2.Network.fault_history_for_sensor!(socket.assigns.sensor.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Fault reported."))
         |> assign(:active_faults, active_faults)
         |> assign(:fault_history, fault_history)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to report fault."))}
    end
  end

  def handle_event("resolve_fault", %{"id" => fault_id}, socket) do
    all_faults = socket.assigns.active_faults ++ socket.assigns.fault_history

    case Enum.find(all_faults, &(&1.id == fault_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Fault not found."))}

      fault ->
        case Voria2.Network.resolve_fault(
               fault,
               %{resolved_by_id: socket.assigns.current_user.id},
               actor: socket.assigns.current_user
             ) do
          {:ok, _} ->
            active_faults = Voria2.Network.active_faults_for_sensor!(socket.assigns.sensor.id)
            fault_history = Voria2.Network.fault_history_for_sensor!(socket.assigns.sensor.id)

            {:noreply,
             socket
             |> put_flash(:info, gettext("Fault resolved."))
             |> assign(:active_faults, active_faults)
             |> assign(:fault_history, fault_history)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to resolve fault."))}
        end
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-3xl">
      <.breadcrumb crumbs={breadcrumbs(assigns)} />

      <.header>
        {if @measurement_type, do: @measurement_type.name, else: gettext("Sensor")}
        <:subtitle>
          {if @station, do: @station.name, else: "—"}
          <span :if={@sensor.model}> ·             {@sensor.model}</span>
        </:subtitle>
        <:actions>
          <.link navigate={~p"/manage/sensors/#{@sensor.id}/edit"} class="btn btn-ghost btn-sm gap-2">
            <.icon name="hero-pencil" class="size-4" /> {gettext("Edit")}
          </.link>
          <button
            :if={is_nil(@sensor.removed_at)}
            class="btn btn-ghost btn-sm text-warning hover:bg-warning/10 gap-2"
            onclick="document.getElementById('decomm-modal').showModal()"
          >
            <.icon name="hero-archive-box" class="size-4" /> {gettext("Decommission")}
          </button>
          <button
            class="btn btn-ghost btn-sm text-error hover:bg-error/10 gap-2"
            onclick="document.getElementById('del-sensor').showModal()"
          >
            <.icon name="hero-trash" class="size-4" /> {gettext("Delete")}
          </button>
        </:actions>
      </.header>

      <.confirm_modal
        id="decomm-modal"
        title={gettext("Decommission Sensor?")}
        message={gettext("This marks the sensor as no longer active. Historical data is preserved.")}
        confirm_label={gettext("Decommission")}
        confirm_event="decommission"
        confirm_value={%{}}
      />
      <.confirm_modal
        id="del-sensor"
        title={gettext("Delete Sensor?")}
        message={gettext("This permanently deletes the sensor and all its measurement data.")}
        confirm_label={gettext("Delete")}
        confirm_event="delete"
        confirm_value={%{}}
        danger={true}
      />

      <div class="space-y-4 mt-2">
        <.detail_section title={gettext("Installation Details")}>
          <:item label={gettext("Status")}>
            <.status_badge
              active={is_nil(@sensor.removed_at)}
              active_label={gettext("Active")}
              inactive_label={gettext("Decommissioned")}
            />
          </:item>
          <:item label={gettext("Type")}>
            {if @measurement_type, do: @measurement_type.name, else: "—"}
          </:item>
          <:item label={gettext("Storage Type")}>
            {if @measurement_type, do: to_string(@measurement_type.storage_type), else: "—"}
          </:item>
          <:item label={gettext("Model")}>{@sensor.model || "—"}</:item>
          <:item label={gettext("Installed On")}>
            {if @sensor.installed_at,
              do: Calendar.strftime(@sensor.installed_at, "%b %d, %Y"),
              else: "—"}
          </:item>
          <:item label={gettext("Removed On")}>
            {if @sensor.removed_at, do: Calendar.strftime(@sensor.removed_at, "%b %d, %Y"), else: "—"}
          </:item>
          <:item label={gettext("Rain Mode")}>
            {if @sensor.rain_mode, do: to_string(@sensor.rain_mode), else: "—"}
          </:item>
          <:item label={gettext("Notes")}>{@sensor.notes || "—"}</:item>
        </.detail_section>

        <div class=" border border-base-300 bg-base-100 overflow-hidden">
          <div class="px-6 py-4 border-b border-base-300 bg-base-200/40">
            <h3 class="text-sm font-semibold">{gettext("Faults")}</h3>
          </div>
          <div class="p-6 space-y-4">
            <form :if={@current_user.admin} phx-submit="report_fault" class="flex gap-3 items-end">
              <div class="flex-1 fieldset mb-0">
                <label for="fault-reason-sensor">
                  <span class="label mb-1">{gettext("Reason")}</span>
                  <input
                    id="fault-reason-sensor"
                    type="text"
                    name="reason"
                    class="w-full input input-sm"
                    placeholder={gettext("e.g. Sensor drift, reading anomaly…")}
                    required
                  />
                </label>
              </div>
              <button type="submit" class="btn btn-warning btn-sm gap-2">
                <.icon name="hero-exclamation-triangle" class="size-4" /> {gettext("Report Fault")}
              </button>
            </form>
            <.fault_list
              faults={@active_faults ++ Enum.filter(@fault_history, &(!is_nil(&1.resolved_at)))}
              can_resolve={@current_user.admin}
              empty_message={gettext("No faults recorded for this sensor.")}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp breadcrumbs(%{
         installation: installation,
         station: station,
         sensor: sensor,
         measurement_type: mt
       }) do
    base = [{gettext("Installations"), ~p"/manage/installations"}]

    base =
      if installation,
        do: base ++ [{installation.name, ~p"/manage/installations/#{installation.id}"}],
        else: base

    base =
      if station,
        do: base ++ [{station.name, ~p"/manage/stations/#{station.id}?tab=sensors"}],
        else: base

    label = if mt, do: mt.name, else: gettext("Sensor") <> " ##{String.slice(sensor.id, 0, 8)}"
    base ++ [{label, nil}]
  end

  defp load_station(nil, _actor), do: nil

  defp load_station(station_id, actor) do
    case Voria2.Network.get_station(station_id, actor: actor) do
      {:ok, s} -> s
      _ -> nil
    end
  end

  defp load_installation(nil, _actor), do: nil

  defp load_installation(installation_id, actor) do
    case Voria2.Network.get_installation(installation_id, actor: actor) do
      {:ok, i} -> i
      _ -> nil
    end
  end
end
