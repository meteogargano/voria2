defmodule Voria2Web.ManageLive.Sensors.Form do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(params, _session, socket) do
    socket = assign(socket, :active_section, :installations)

    measurement_types =
      Voria2.Measurements.list_measurement_types!(actor: socket.assigns.current_user)

    socket =
      case socket.assigns.live_action do
        :new ->
          station_id = params["station_id"]

          case Voria2.Network.get_station(station_id, actor: socket.assigns.current_user) do
            {:ok, station} ->
              installation =
                load_installation(station.installation_id, socket.assigns.current_user)

              form =
                AshPhoenix.Form.for_create(
                  Voria2.Measurements.SensorInstallation,
                  :create,
                  actor: socket.assigns.current_user
                )
                |> to_form()

              socket
              |> assign(:page_title, gettext("Add Sensor"))
              |> assign(:form, form)
              |> assign(:station, station)
              |> assign(:installation, installation)
              |> assign(:sensor, nil)
              |> assign(:measurement_types, measurement_types)

            {:error, _} ->
              socket
              |> put_flash(:error, gettext("Station not found."))
              |> push_navigate(to: ~p"/manage/installations")
          end

        :edit ->
          id = params["id"]

          case Voria2.Measurements.get_sensor_installation(id, actor: socket.assigns.current_user) do
            {:ok, sensor} ->
              station = load_station(sensor.station_id, socket.assigns.current_user)

              installation =
                if station,
                  do: load_installation(station.installation_id, socket.assigns.current_user),
                  else: nil

              form =
                AshPhoenix.Form.for_update(
                  sensor,
                  :update,
                  actor: socket.assigns.current_user
                )
                |> to_form()

              socket
              |> assign(:page_title, gettext("Edit Sensor"))
              |> assign(:form, form)
              |> assign(:station, station)
              |> assign(:installation, installation)
              |> assign(:sensor, sensor)
              |> assign(:measurement_types, measurement_types)

            {:error, _} ->
              socket
              |> put_flash(:error, gettext("Sensor not found."))
              |> push_navigate(to: ~p"/manage/installations")
          end
      end

    {:ok, socket}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params) |> to_form()
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    params =
      if socket.assigns.live_action == :new do
        Map.put(params, "station_id", socket.assigns.station.id)
      else
        params
      end

    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _sensor} ->
        message =
          if socket.assigns.live_action == :new,
            do: gettext("Sensor added."),
            else: gettext("Sensor updated.")

        redirect_to =
          if socket.assigns.station,
            do: ~p"/manage/stations/#{socket.assigns.station.id}?tab=sensors",
            else: ~p"/manage/installations"

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: redirect_to)}

      {:error, form} ->
        {:noreply, assign(socket, :form, form |> to_form())}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <.breadcrumb crumbs={breadcrumbs(assigns)} />

      <.header>
        {@page_title}
        <:subtitle :if={@live_action == :new && @station}>
          {gettext("Adding a sensor to %{name}.", name: @station.name)}
        </:subtitle>
      </.header>

      <div class="mt-4">
        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class=" border border-base-300 bg-base-100 divide-y divide-base-300 overflow-hidden">
            <div class="px-6 py-4 bg-base-200/40">
              <h3 class="text-sm font-semibold">{gettext("Sensor Details")}</h3>
            </div>
            <div class="px-6 py-5 space-y-4">
              <.input
                :if={@live_action == :new}
                field={@form[:measurement_type_id]}
                type="select"
                label={gettext("Measurement Type")}
                prompt={gettext("Select a type...")}
                options={Enum.map(@measurement_types, &{&1.name <> " (#{&1.storage_type})", &1.id})}
              />

              <div class="grid grid-cols-2 gap-4">
                <.input
                  field={@form[:installed_at]}
                  type="date"
                  label={gettext("Installed On")}
                />
                <.input
                  field={@form[:removed_at]}
                  type="date"
                  label={gettext("Removed On (if decommissioned)")}
                />
              </div>

              <.input
                field={@form[:model]}
                type="text"
                label={gettext("Model")}
                placeholder={gettext("DHT22, BME280, etc.")}
              />
              <.input
                field={@form[:notes]}
                type="textarea"
                label={gettext("Notes")}
                placeholder={gettext("Installation notes, calibration details...")}
                rows="3"
              />

              <.input
                field={@form[:rain_mode]}
                type="select"
                label={gettext("Rain Mode")}
                prompt={gettext("Not applicable")}
                options={[
                  {gettext("Interval (mm per reading)"), "interval"},
                  {gettext("Cumulative (total mm)"), "cumulative"}
                ]}
              />
            </div>
          </div>

          <div class="flex justify-end gap-3 mt-4">
            <.link
              navigate={
                if @station,
                  do: ~p"/manage/stations/#{@station.id}?tab=sensors",
                  else: ~p"/manage/installations"
              }
              class="btn btn-ghost btn-sm"
            >
              {gettext("Cancel")}
            </.link>
            <.button type="submit" variant="primary">
              {if @live_action == :new, do: gettext("Add Sensor"), else: gettext("Save Changes")}
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp breadcrumbs(%{
         installation: installation,
         station: station,
         live_action: action,
         sensor: _sensor
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

    base ++ [{if(action == :new, do: gettext("Add Sensor"), else: gettext("Edit Sensor")), nil}]
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
