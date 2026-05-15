defmodule Voria2Web.ManageLive.Stations.Show do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Voria2.Network.get_station(id, actor: socket.assigns.current_user) do
      {:ok, station} ->
        installation =
          case Voria2.Network.get_installation(station.installation_id,
                 actor: socket.assigns.current_user
               ) do
            {:ok, i} -> i
            _ -> nil
          end

        api_keys = load_station_api_keys(station.id, socket.assigns.current_user)
        sensors = load_sensors_for_station(station.id, socket.assigns.current_user)
        active_faults = Voria2.Network.active_faults_for_station!(station.id)
        fault_history = Voria2.Network.fault_history_for_station!(station.id)

        {:ok,
         socket
         |> assign(:page_title, station.name)
         |> assign(:active_section, :installations)
         |> assign(:station, station)
         |> assign(:installation, installation)
         |> assign(:api_keys, api_keys)
         |> assign(:sensors, sensors)
         |> assign(:active_faults, active_faults)
         |> assign(:fault_history, fault_history)
         |> assign(:active_tab, :overview)
         |> assign(:generated_key, nil)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Station not found."))
         |> push_navigate(to: ~p"/manage/installations")}
    end
  end

  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        "sensors" -> :sensors
        "api_keys" -> :api_keys
        "faults" -> :faults
        _ -> :overview
      end

    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("generate_key", %{"label" => label}, socket) do
    label = if label == "", do: nil, else: label

    case Voria2.Network.generate_station_api_key_labeled(
           socket.assigns.station.id,
           label,
           actor: socket.assigns.current_user
         ) do
      {:ok, api_key} ->
        api_keys =
          load_station_api_keys(socket.assigns.station.id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(:api_keys, api_keys)
         |> assign(:generated_key, api_key.key)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to generate API key."))}
    end
  end

  def handle_event("close_key_modal", _params, socket) do
    {:noreply, assign(socket, :generated_key, nil)}
  end

  def handle_event("revoke_key", %{"id" => id}, socket) do
    all_keys = Voria2.Network.list_station_api_keys!(actor: socket.assigns.current_user)

    case Enum.find(all_keys, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("API key not found."))}

      key ->
        case Voria2.Network.revoke_station_api_key(key,
               actor: socket.assigns.current_user
             ) do
          :ok ->
            api_keys =
              load_station_api_keys(socket.assigns.station.id, socket.assigns.current_user)

            {:noreply,
             socket
             |> put_flash(:info, gettext("API key revoked."))
             |> assign(:api_keys, api_keys)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to revoke key."))}
        end
    end
  end

  def handle_event("decommission_sensor", %{"id" => id}, socket) do
    all_sensors =
      Voria2.Measurements.list_sensor_installations!(actor: socket.assigns.current_user)

    case Enum.find(all_sensors, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Sensor not found."))}

      sensor ->
        case Voria2.Measurements.decommission_sensor(sensor,
               actor: socket.assigns.current_user
             ) do
          {:ok, _} ->
            sensors =
              load_sensors_for_station(socket.assigns.station.id, socket.assigns.current_user)

            {:noreply,
             socket
             |> put_flash(:info, gettext("Sensor decommissioned."))
             |> assign(:sensors, sensors)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to decommission sensor."))}
        end
    end
  end

  def handle_event("delete_station", _params, socket) do
    case Voria2.Network.destroy_station(
           socket.assigns.station,
           actor: socket.assigns.current_user
         ) do
      :ok ->
        redirect_path =
          if socket.assigns.installation,
            do: ~p"/manage/installations/#{socket.assigns.installation.id}",
            else: ~p"/manage/installations"

        {:noreply,
         socket
         |> put_flash(:info, gettext("Station deleted."))
         |> push_navigate(to: redirect_path)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete station."))}
    end
  end

  def handle_event("report_fault", %{"reason" => reason}, socket) do
    case Voria2.Network.report_manual_fault(
           %{
             station_id: socket.assigns.station.id,
             reason: reason,
             detected_at: DateTime.utc_now()
           },
           actor: socket.assigns.current_user
         ) do
      {:ok, _} ->
        active_faults = Voria2.Network.active_faults_for_station!(socket.assigns.station.id)
        fault_history = Voria2.Network.fault_history_for_station!(socket.assigns.station.id)

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
            active_faults =
              Voria2.Network.active_faults_for_station!(socket.assigns.station.id)

            fault_history =
              Voria2.Network.fault_history_for_station!(socket.assigns.station.id)

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
    <div class="max-w-5xl">
      <.breadcrumb crumbs={[
        {gettext("Installations"), ~p"/manage/installations"},
        {if(@installation, do: @installation.name, else: "…"),
         if(@installation,
           do: ~p"/manage/installations/#{@installation.id}",
           else: ~p"/manage/installations"
         )},
        {@station.name, nil}
      ]} />

      <.header>
        {@station.name}
        <:subtitle>
          <code class="font-mono text-xs">{@station.slug}</code>
        </:subtitle>
        <:actions>
          <.link
            navigate={~p"/manage/stations/#{@station.id}/edit"}
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="hero-pencil" class="size-4" /> {gettext("Edit")}
          </.link>
          <button
            class="btn btn-ghost btn-sm text-error hover:bg-error/10 gap-2"
            onclick="document.getElementById('del-station').showModal()"
          >
            <.icon name="hero-trash" class="size-4" /> {gettext("Delete")}
          </button>
        </:actions>
      </.header>

      <.confirm_modal
        id="del-station"
        title={gettext("Delete %{name}?", name: @station.name)}
        message={
          gettext(
            "This will permanently delete all sensors, measurements, and API keys for this station."
          )
        }
        confirm_label={gettext("Delete Station")}
        confirm_event="delete_station"
        confirm_value={%{}}
        danger={true}
      />

      <.tab_bar
        tabs={[
          {:overview, gettext("Overview"), ~p"/manage/stations/#{@station.id}"},
          {:sensors, gettext("Sensors (%{count})", count: length(@sensors)),
           ~p"/manage/stations/#{@station.id}?tab=sensors"},
          {:api_keys, gettext("API Keys (%{count})", count: length(@api_keys)),
           ~p"/manage/stations/#{@station.id}?tab=api_keys"},
          {:faults, gettext("Faults"), ~p"/manage/stations/#{@station.id}?tab=faults"}
        ]}
        active_tab={@active_tab}
      />

      <%!-- Overview --%>
      <div :if={@active_tab == :overview}>
        <.detail_section title={gettext("Details")}>
          <:item label={gettext("Status")}><.status_badge active={@station.is_active} /></:item>
          <:item label={gettext("Slug")}>
            <code class="font-mono text-xs bg-base-200 px-1.5 py-0.5">{@station.slug}</code>
          </:item>
          <:item label={gettext("Description")}>
            {if @station.description, do: @station.description, else: "—"}
          </:item>
          <:item label={gettext("Installation")}>
            <.link
              :if={@installation}
              navigate={~p"/manage/installations/#{@installation.id}"}
              class="hover:text-primary"
            >
              {@installation.name}
            </.link>
          </:item>
          <:item label={gettext("Created")}>
            {Calendar.strftime(@station.inserted_at, "%b %d, %Y")}
          </:item>
        </.detail_section>
      </div>

      <%!-- Sensors Tab --%>
      <div :if={@active_tab == :sensors}>
        <div class="flex justify-end mb-4">
          <.link
            navigate={~p"/manage/stations/#{@station.id}/sensors/new"}
            class="btn btn-primary btn-sm gap-2"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("Add Sensor")}
          </.link>
        </div>
        <.resource_table
          id="sensors-table"
          rows={@sensors}
          empty_title={gettext("No sensors installed")}
          empty_message={gettext("Add a sensor installation to start collecting measurements.")}
          empty_icon="hero-cpu-chip"
        >
          <:empty_actions>
            <.link
              navigate={~p"/manage/stations/#{@station.id}/sensors/new"}
              class="btn btn-primary btn-sm gap-2"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("Add Sensor")}
            </.link>
          </:empty_actions>
          <:col :let={s} label={gettext("Type")}>
            <.link navigate={~p"/manage/sensors/#{s.id}"} class="font-medium hover:text-primary">
              {sensor_label(s)}
            </.link>
          </:col>
          <:col :let={s} label={gettext("Installed")}>
            {if s.installed_at, do: Calendar.strftime(s.installed_at, "%b %d, %Y"), else: "—"}
          </:col>
          <:col :let={s} label={gettext("Model")}>
            {s.model || "—"}
          </:col>
          <:col :let={s} label={gettext("Status")}>
            <.status_badge
              active={is_nil(s.removed_at)}
              active_label={gettext("Active")}
              inactive_label={gettext("Decommissioned")}
            />
          </:col>
          <:action :let={s}>
            <.link navigate={~p"/manage/sensors/#{s.id}"} class="btn btn-ghost btn-xs">
              <.icon name="hero-eye" class="size-3.5" />
            </.link>
            <.link navigate={~p"/manage/sensors/#{s.id}/edit"} class="btn btn-ghost btn-xs">
              <.icon name="hero-pencil" class="size-3.5" />
            </.link>
            <button
              :if={is_nil(s.removed_at)}
              class="btn btn-ghost btn-xs text-warning hover:bg-warning/10"
              onclick={"document.getElementById('decomm-#{s.id}').showModal()"}
            >
              <.icon name="hero-archive-box" class="size-3.5" />
            </button>
            <.confirm_modal
              :if={is_nil(s.removed_at)}
              id={"decomm-#{s.id}"}
              title={gettext("Decommission Sensor?")}
              message={
                gettext("This marks the sensor as no longer active. Historical data is preserved.")
              }
              confirm_label={gettext("Decommission")}
              confirm_event="decommission_sensor"
              confirm_value={%{id: s.id}}
            />
          </:action>
        </.resource_table>
      </div>

      <%!-- API Keys Tab --%>
      <div :if={@active_tab == :api_keys}>
        <%!-- Key reveal modal (shown after generation) --%>
        <.key_reveal_modal :if={@generated_key} id="new-key-modal" key={@generated_key} />

        <div class="mb-6">
          <form phx-submit="generate_key" class="flex gap-3 items-end">
            <div class="flex-1 fieldset mb-0">
              <label for="key-label">
                <span class="label mb-1">{gettext("Label (optional)")}</span>
                <input
                  id="key-label"
                  type="text"
                  name="label"
                  class="w-full input input-sm"
                  placeholder="e.g. Raspberry Pi #1"
                />
              </label>
            </div>
            <button type="submit" class="btn btn-primary btn-sm gap-2">
              <.icon name="hero-key" class="size-4" /> {gettext("Generate Key")}
            </button>
          </form>
        </div>

        <div :if={@api_keys == []} class="text-center py-12 text-base-content/50 text-sm">
          {gettext("No API keys yet. Generate one to start ingesting data.")}
        </div>
        <div :if={@api_keys != []} class="space-y-2">
          <.api_key_card
            :for={key <- @api_keys}
            api_key={key}
            revoke_event="revoke_key"
            modal_id="revoke-key"
          />
        </div>
      </div>

      <%!-- Faults Tab --%>
      <div :if={@active_tab == :faults}>
        <div :if={@current_user.admin} class="mb-6">
          <form phx-submit="report_fault" class="flex gap-3 items-end">
            <div class="flex-1 fieldset mb-0">
              <label for="fault-reason-station">
                <span class="label mb-1">{gettext("Reason")}</span>
                <input
                  id="fault-reason-station"
                  type="text"
                  name="reason"
                  class="w-full input input-sm"
                  placeholder={gettext("e.g. Hardware failure, sensor disconnected…")}
                  required
                />
              </label>
            </div>
            <button type="submit" class="btn btn-warning btn-sm gap-2">
              <.icon name="hero-exclamation-triangle" class="size-4" /> {gettext("Report Fault")}
            </button>
          </form>
        </div>

        <div :if={@active_faults != []} class="mb-6">
          <h3 class="text-sm font-semibold text-error mb-3">{gettext("Active Faults")}</h3>
          <.fault_list
            faults={@active_faults}
            can_resolve={@current_user.admin}
            empty_message={gettext("No active faults.")}
          />
        </div>
        <div>
          <h3 class="text-sm font-semibold text-base-content/60 mb-3">{gettext("Fault History")}</h3>
          <.fault_list
            faults={Enum.filter(@fault_history, &(!is_nil(&1.resolved_at)))}
            can_resolve={false}
            empty_message={gettext("No fault history.")}
          />
        </div>
      </div>
    </div>
    """
  end

  defp load_station_api_keys(station_id, actor) do
    Voria2.Network.list_station_api_keys!(actor: actor)
    |> Enum.filter(&(&1.station_id == station_id))
  end

  defp load_sensors_for_station(station_id, actor) do
    Voria2.Measurements.list_sensor_installations!(actor: actor, load: [:measurement_type])
    |> Enum.filter(&(&1.station_id == station_id))
  end

  defp sensor_label(sensor) do
    case sensor.measurement_type do
      %{name: name} -> name
      _ -> "Sensor"
    end
  end
end
