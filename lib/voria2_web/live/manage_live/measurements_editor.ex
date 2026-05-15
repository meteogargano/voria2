defmodule Voria2Web.ManageLive.MeasurementsEditor do
  use Voria2Web, :live_view

  import Voria2Web.FlatpickrInputComponent

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user

    stations =
      Voria2.Network.list_stations!(actor: actor, load: [:installation])

    measurement_types =
      Voria2.Measurements.list_measurement_types!(actor: actor)

    {:ok,
     socket
     |> assign(:page_title, gettext("Measurements Editor"))
     |> assign(:active_section, :measurements_editor)
     |> assign(:stations, stations)
     |> assign(:measurement_types, measurement_types)
     |> assign(:selected_station_id, nil)
     |> assign(:selected_type_id, nil)
     |> assign(:date_from, nil)
     |> assign(:date_to, nil)
     |> assign(:measurements, [])
     |> assign(:sensor, nil)
     |> assign(:storage_type, nil)
     |> assign(:editing_id, nil)
     |> assign(:edit_form, %{})
     |> assign(:loading, false)
     |> assign(:changes_made, false)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("load_data", _params, socket) do
    station_id = socket.assigns.selected_station_id
    type_id = socket.assigns.selected_type_id

    cond do
      is_nil(station_id) ->
        {:noreply, put_flash(socket, :error, gettext("Please select a station."))}

      is_nil(type_id) ->
        {:noreply, put_flash(socket, :error, gettext("Please select a measurement type."))}

      is_nil(socket.assigns.date_from) or is_nil(socket.assigns.date_to) ->
        {:noreply, put_flash(socket, :error, gettext("Please select a date range."))}

      not validate_date_range(socket.assigns.date_from, socket.assigns.date_to) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Date range cannot exceed 24 hours.")
         )}

      true ->
        load_and_assign_measurements(socket)
    end
  end

  @impl true
  def handle_event("handle_filter_change", params, socket) do
    socket =
      case Map.fetch(params, "station_id") do
        {:ok, station_id} ->
          assign(socket, :selected_station_id, if(station_id == "", do: nil, else: station_id))

        :error ->
          socket
      end

    socket =
      case Map.fetch(params, "type_id") do
        {:ok, type_id} ->
          assign(socket, :selected_type_id, if(type_id == "", do: nil, else: type_id))

        :error ->
          socket
      end

    socket =
      case Map.fetch(params, "date_from") do
        {:ok, date_str} when date_str != "" ->
          case parse_datetime(date_str) do
            {:ok, datetime} ->
              assign(socket, :date_from, datetime)

            :error ->
              put_flash(socket, :error, gettext("Invalid date format."))
          end

        _ ->
          socket
      end

    socket =
      case Map.fetch(params, "date_to") do
        {:ok, date_str} when date_str != "" ->
          case parse_datetime(date_str) do
            {:ok, datetime} ->
              assign(socket, :date_to, datetime)

            :error ->
              put_flash(socket, :error, gettext("Invalid date format."))
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    measurement =
      Enum.find(socket.assigns.measurements, fn m -> m.id == id end)

    {:noreply,
     socket
     |> assign(:editing_id, id)
     |> assign(:edit_form, %{
       "measured_at" => format_datetime_input(measurement.measured_at),
       "value" => measurement_value_to_string(measurement, socket.assigns.storage_type),
       "u" => to_string(Map.get(measurement, :u) || ""),
       "v" => to_string(Map.get(measurement, :v) || ""),
       "gust" => to_string(Map.get(measurement, :gust) || ""),
       "interval_mm" => to_string(Map.get(measurement, :interval_mm) || ""),
       "raw" => format_raw_value(Map.get(measurement, :raw))
     })}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_id, nil)
     |> assign(:edit_form, %{})}
  end

  @impl true
  def handle_event("update_edit_form", params, socket) do
    {:noreply, assign(socket, :edit_form, Map.merge(socket.assigns.edit_form, params))}
  end

  @impl true
  def handle_event("save", %{"id" => id}, socket) do
    IO.puts("DEBUG SAVE: #{id}")
    IO.inspect(socket.assigns.storage_type, label: "STORAGE_TYPE")

    measurement =
      Enum.find(socket.assigns.measurements, fn m -> m.id == id end)

    IO.inspect(measurement, label: "MEASUREMENT")

    storage_type = socket.assigns.storage_type

    IO.inspect(socket.assigns.edit_form, label: "EDIT_FORM")

    result = update_measurement(measurement, socket.assigns.edit_form, storage_type, socket)
    IO.inspect(result, label: "UPDATE_RESULT")

    case result do
      {:ok, _updated} ->
        station_id = socket.assigns.sensor.station_id

        # Recalculate summaries
        case Voria2.Measurements.recalculate_summaries_for_station(station_id,
               actor: socket.assigns.current_user
             ) do
          :ok ->
            :ok

          {:error, _reason} ->
            nil
        end

        # Reload measurements and clear edit state
        socket =
          socket
          |> assign(:editing_id, nil)
          |> assign(:edit_form, %{})
          |> assign(:changes_made, false)

        load_and_assign_measurements(socket)

      {:error, changeset} ->
        errors =
          changeset.errors
          |> Enum.map(fn {field, {msg, _opts}} ->
            "#{field_to_label(field)}: #{msg}"
          end)
          |> Enum.join(", ")

        {:noreply,
         put_flash(socket, :error, gettext("Failed to save: %{errors}", errors: errors))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl">
      <.breadcrumb crumbs={[{gettext("Manage"), ~p"/manage"}, {gettext("Measurements Editor"), nil}]} />

      <.header>
        {gettext("Measurements Editor")}
        <:subtitle>
          {gettext(
            "Edit measurement values to correct broken data. Changes will trigger summary recalculation."
          )}
        </:subtitle>
      </.header>

      <form phx-change="handle_filter_change" phx-target="form" id="filter-form">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4 mt-2">
          <fieldset>
            <label for="station-select">
              <span class="label mb-1">{gettext("Station")}</span>
              <select
                id="station-select"
                name="station_id"
                class="select select-sm w-full"
              >
                <option value="">{gettext("Select a station...")}</option>
                <option
                  :for={station <- @stations}
                  value={station.id}
                  selected={@selected_station_id == station.id}
                >
                  {station.name}
                </option>
              </select>
            </label>
          </fieldset>

          <fieldset>
            <label for="type-select">
              <span class="label mb-1">{gettext("Measurement Type")}</span>
              <select
                id="type-select"
                name="type_id"
                class="select select-sm w-full"
              >
                <option value="">{gettext("Select a type...")}</option>
                <option
                  :for={mt <- @measurement_types}
                  value={mt.id}
                  selected={@selected_type_id == mt.id}
                >
                  {mt.name}
                </option>
              </select>
            </label>
          </fieldset>

          <fieldset>
            <.datetime_picker
              id="date-from"
              field_name="date_from"
              label={gettext("From")}
              value={format_datetime_input(@date_from)}
              input_class="input input-sm w-full"
            />
          </fieldset>

          <fieldset>
            <.datetime_picker
              id="date-to"
              field_name="date_to"
              label={gettext("To")}
              value={format_datetime_input(@date_to)}
              input_class="input input-sm w-full"
            />
          </fieldset>
        </div>
      </form>

      <button
        :if={!@loading}
        class="btn btn-primary btn-sm gap-2 mb-6"
        phx-click="load_data"
        disabled={is_nil(@selected_station_id) or is_nil(@selected_type_id)}
      >
        <.icon name="hero-magnifying-glass" class="size-4" /> {gettext("Load Measurements")}
      </button>

      <div :if={@loading} class="flex justify-center py-12">
        <span class="loading loading-spinner"></span>
      </div>

      <div :if={@measurements != []}>
        <div class="mb-4">
          <h3 class="text-sm font-semibold mb-2">
            {@sensor.station.name} — {@sensor.measurement_type.name}
            <span class="text-base-content/50 font-normal ml-2">
              ({ngettext("(%{count} reading)", "(%{count} readings)", length(@measurements))})
            </span>
          </h3>
        </div>

        <div class="overflow-x-auto  border border-base-300">
          <table class="table table-zebra w-full">
            <thead>
              <tr class="bg-base-200/60">
                <th class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                  {gettext("Timestamp")}
                </th>
                <%= if @storage_type in [:scalar, :custom] do %>
                  <th class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    {gettext("Value")}
                  </th>
                <% end %>
                <%= if @storage_type == :wind do %>
                  <th class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    u (m/s)
                  </th>
                  <th class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    v (m/s)
                  </th>
                  <th class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    {gettext("gust (m/s)")}
                  </th>
                  <th class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    {gettext("Speed (m/s)")}
                  </th>
                  <th class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    {gettext("Direction (°)")}
                  </th>
                <% end %>
                <%= if @storage_type == :rain do %>
                  <th class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    {gettext("Interval (mm)")}
                  </th>
                <% end %>
                <%= if @storage_type == :custom do %>
                  <th class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    {gettext("Raw")}
                  </th>
                <% end %>
                <th class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                  <span class="sr-only">{gettext("Actions")}</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <%= for measurement <- @measurements do %>
                <tr class="hover">
                  <%= if @editing_id == measurement.id do %>
                    <td class="py-2">
                      <.datetime_picker
                        id={"edit-measured-at-#{measurement.id}"}
                        field_name="measured_at"
                        value={@edit_form["measured_at"]}
                        push_event="update_edit_form"
                        input_class="input input-xs w-full"
                      />
                    </td>

                    <%= if @storage_type in [:scalar, :custom] do %>
                      <td class="py-2">
                        <input
                          type="number"
                          name="value"
                          id="edit-value-#{measurement.id}"
                          class="input input-xs w-full"
                          value={@edit_form["value"]}
                          step="any"
                          phx-hook="InputBlur"
                        />
                      </td>
                    <% end %>

                    <%= if @storage_type == :wind do %>
                      <td class="py-2">
                        <input
                          type="number"
                          name="u"
                          id="edit-u-#{measurement.id}"
                          class="input input-xs w-full"
                          value={@edit_form["u"]}
                          step="any"
                          phx-hook="InputBlur"
                        />
                      </td>
                      <td class="py-2">
                        <input
                          type="number"
                          name="v"
                          id="edit-v-#{measurement.id}"
                          class="input input-xs w-full"
                          value={@edit_form["v"]}
                          step="any"
                          phx-hook="InputBlur"
                        />
                      </td>
                      <td class="py-2">
                        <input
                          type="number"
                          name="gust"
                          id="edit-gust-#{measurement.id}"
                          class="input input-xs w-full"
                          value={@edit_form["gust"]}
                          step="any"
                          phx-hook="InputBlur"
                        />
                      </td>
                      <td class="py-2 text-center text-base-content/50">
                        {wind_speed(measurement.u, measurement.v)}
                      </td>
                      <td class="py-2 text-center text-base-content/50">
                        {wind_direction(measurement.u, measurement.v)}
                      </td>
                    <% end %>

                    <%= if @storage_type == :rain do %>
                      <td class="py-2">
                        <input
                          type="number"
                          name="interval_mm"
                          id="edit-interval-mm-#{measurement.id}"
                          class="input input-xs w-full"
                          value={@edit_form["interval_mm"]}
                          step="any"
                          min="0"
                          phx-hook="InputBlur"
                        />
                      </td>
                    <% end %>

                    <%= if @storage_type == :custom do %>
                      <td class="py-2">
                        <textarea
                          name="raw"
                          id="edit-raw-#{measurement.id}"
                          class="textarea textarea-xs w-full"
                          rows="2"
                          phx-hook="InputBlur"
                        >
                          {@edit_form["raw"]}
                        </textarea>
                      </td>
                    <% end %>

                    <td class="py-2 w-px">
                      <div class="flex gap-1">
                        <button
                          class="btn btn-success btn-xs"
                          phx-click="save"
                          phx-value-id={measurement.id}
                        >
                          {gettext("Save")}
                        </button>
                        <button
                          class="btn btn-ghost btn-xs"
                          phx-click="cancel_edit"
                        >
                          {gettext("Cancel")}
                        </button>
                      </div>
                    </td>
                  <% else %>
                    <td class="py-2">
                      {format_datetime(measurement.measured_at)}
                    </td>

                    <%= if @storage_type in [:scalar, :custom] do %>
                      <td class="py-2 font-mono">{measurement.value}</td>
                    <% end %>

                    <%= if @storage_type == :wind do %>
                      <td class="py-2 font-mono">{measurement.u}</td>
                      <td class="py-2 font-mono">{measurement.v}</td>
                      <td class="py-2 font-mono">
                        {if is_nil(measurement.gust), do: "—", else: measurement.gust}
                      </td>
                      <td class="py-2 font-mono text-center text-base-content/50">
                        {measurement.speed}
                      </td>
                      <td class="py-2 font-mono text-center text-base-content/50">
                        {measurement.direction_deg}
                      </td>
                    <% end %>

                    <%= if @storage_type == :rain do %>
                      <td class="py-2 font-mono">{measurement.interval_mm}</td>
                    <% end %>

                    <%= if @storage_type == :custom do %>
                      <td class="py-2">
                        <code class="text-xs">
                          {format_raw_value_display(measurement.raw)}
                        </code>
                      </td>
                    <% end %>

                    <td class="py-2 w-px">
                      <button
                        class="btn btn-ghost btn-xs"
                        phx-click="edit"
                        phx-value-id={measurement.id}
                      >
                        <.icon name="hero-pencil" class="size-3.5" />
                      </button>
                    </td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <div :if={@measurements == [] and !@loading}>
        <.empty_state
          title={gettext("No measurements loaded")}
          message={
            gettext("Select a station, measurement type, and date range to load measurements.")
          }
          icon="hero-chart-bar"
        />
      </div>
    </div>
    """
  end

  # Private helpers

  defp load_and_assign_measurements(socket) do
    actor = socket.assigns.current_user
    station_id = socket.assigns.selected_station_id
    type_id = socket.assigns.selected_type_id
    from = socket.assigns.date_from
    to = socket.assigns.date_to

    # Find sensor for station and type
    sensors =
      Voria2.Measurements.list_sensor_installations!(
        actor: actor,
        load: [:measurement_type, :station]
      )
      |> Enum.filter(fn s ->
        s.station_id == station_id and s.measurement_type_id == type_id
      end)

    case sensors do
      [sensor] ->
        measurements = load_measurements_for_sensor(sensor, from, to, actor)

        {:noreply,
         socket
         |> assign(:sensor, sensor)
         |> assign(:storage_type, sensor.measurement_type.storage_type)
         |> assign(:measurements, measurements)
         |> assign(:loading, false)
         |> put_flash(
           :info,
           ngettext(
             "Loaded %{count} measurement.",
             "Loaded %{count} measurements.",
             length(measurements)
           )
         )}

      [] ->
        {:noreply,
         socket
         |> assign(:sensor, nil)
         |> assign(:storage_type, nil)
         |> assign(:measurements, [])
         |> assign(:loading, false)
         |> put_flash(:error, gettext("No active sensor found for this station and type."))}

      _multiple ->
        {:noreply,
         socket
         |> assign(:sensor, nil)
         |> assign(:storage_type, nil)
         |> assign(:measurements, [])
         |> assign(:loading, false)
         |> put_flash(
           :error,
           gettext("Multiple sensors found. Please contact administrator.")
         )}
    end
  end

  defp load_measurements_for_sensor(sensor, from, to, actor) do
    case sensor.measurement_type.storage_type do
      :scalar ->
        # Try each scalar type
        case load_by_scalar_type(sensor, from, to, actor) do
          {:ok, measurements} -> measurements
          _error -> []
        end

      :wind ->
        case Voria2.Measurements.wind_for_sensor(sensor.id, from, to, actor: actor) do
          {:ok, measurements} -> measurements
          _error -> []
        end

      :rain ->
        case Voria2.Measurements.rain_for_sensor(sensor.id, from, to, actor: actor) do
          {:ok, measurements} -> measurements
          _error -> []
        end

      :custom ->
        case Voria2.Measurements.custom_for_sensor(sensor.id, from, to, actor: actor) do
          {:ok, measurements} -> measurements
          _error -> []
        end
    end
  end

  defp load_by_scalar_type(sensor, from, to, actor) do
    case sensor.measurement_type.slug do
      "temperature" ->
        Voria2.Measurements.temperature_for_sensor(sensor.id, from, to, actor: actor)

      "humidity" ->
        Voria2.Measurements.humidity_for_sensor(sensor.id, from, to, actor: actor)

      "pressure" ->
        Voria2.Measurements.pressure_for_sensor(sensor.id, from, to, actor: actor)

      _ ->
        {:error, :unknown_type}
    end
  end

  defp validate_date_range(from, to) do
    diff_seconds = DateTime.diff(to, from, :second)
    diff_seconds <= 86_400
  end

  defp parse_datetime(str) when is_binary(str) and str != "" do
    str_with_seconds =
      if String.length(str) == 16 do
        str <> ":00"
      else
        str
      end

    case NaiveDateTime.from_iso8601(str_with_seconds) do
      {:ok, naive} ->
        {:ok, DateTime.from_naive!(naive, "Etc/UTC")}

      {:error, _} ->
        :error
    end
  end

  defp parse_datetime(_), do: :error

  defp format_datetime_input(nil), do: ""

  defp format_datetime_input(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M")
  end

  defp format_datetime(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%b %d, %Y %H:%M")
  end

  defp measurement_value_to_string(measurement, storage_type)
       when storage_type in [:scalar, :custom] do
    to_string(measurement.value)
  end

  defp measurement_value_to_string(_measurement, _storage_type), do: ""

  defp format_raw_value(nil), do: ""

  defp format_raw_value(map) when is_map(map) do
    map
    |> Jason.encode!()
  end

  defp format_raw_value(_), do: ""

  defp format_raw_value_display(nil), do: "—"

  defp format_raw_value_display(map) when is_map(map) do
    map
    |> Jason.encode!(pretty: true)
  end

  defp format_raw_value_display(_), do: "—"

  defp update_measurement(measurement, form_data, storage_type, socket) do
    attrs = prepare_update_attrs(form_data, storage_type)
    actor = socket.assigns.current_user

    case storage_type do
      :scalar ->
        update_scalar_measurement(measurement, attrs, actor)

      :wind ->
        Voria2.Measurements.update_wind(measurement, attrs, actor: actor)

      :rain ->
        Voria2.Measurements.update_rain(measurement, attrs, actor: actor)

      :custom ->
        Voria2.Measurements.update_custom(measurement, attrs, actor: actor)
    end
  end

  defp update_scalar_measurement(measurement, attrs, actor) do
    # Try each scalar type
    case measurement.__struct__ do
      Voria2.Measurements.TemperatureMeasurement ->
        Voria2.Measurements.update_temperature(measurement, attrs, actor: actor)

      Voria2.Measurements.HumidityMeasurement ->
        Voria2.Measurements.update_humidity(measurement, attrs, actor: actor)

      Voria2.Measurements.PressureMeasurement ->
        Voria2.Measurements.update_pressure(measurement, attrs, actor: actor)

      _ ->
        {:error, :unknown_type}
    end
  end

  defp prepare_update_attrs(form_data, storage_type) do
    attrs = %{}

    attrs =
      if form_data["measured_at"] && form_data["measured_at"] != "" do
        Map.put(attrs, :measured_at, parse_datetime!(form_data["measured_at"]))
      else
        attrs
      end

    case storage_type do
      :scalar ->
        if form_data["value"] && form_data["value"] != "" do
          {val, _} = Float.parse(form_data["value"])
          Map.put(attrs, :value, val)
        else
          attrs
        end

      :wind ->
        attrs = maybe_put_float(attrs, form_data, "u")
        attrs = maybe_put_float(attrs, form_data, "v")
        maybe_put_float(attrs, form_data, "gust")

      :rain ->
        if form_data["interval_mm"] && form_data["interval_mm"] != "" do
          {val, _} = Float.parse(form_data["interval_mm"])
          Map.put(attrs, :interval_mm, val)
        else
          attrs
        end

      :custom ->
        attrs =
          if form_data["value"] && form_data["value"] != "" do
            {val, _} = Float.parse(form_data["value"])
            Map.put(attrs, :value, val)
          else
            attrs
          end

        if form_data["raw"] && form_data["raw"] != "" do
          case Jason.decode(form_data["raw"]) do
            {:ok, raw_map} ->
              Map.put(attrs, :raw, raw_map)

            _error ->
              attrs
          end
        else
          attrs
        end
    end
  end

  defp maybe_put_float(attrs, form_data, key) do
    if form_data[key] && form_data[key] != "" do
      {val, _} = Float.parse(form_data[key])
      Map.put(attrs, String.to_atom(key), val)
    else
      attrs
    end
  end

  defp parse_datetime!(str) when is_binary(str) do
    str_with_seconds =
      if String.length(str) == 16 do
        str <> ":00"
      else
        str
      end

    {:ok, naive} = NaiveDateTime.from_iso8601(str_with_seconds)
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp wind_speed(u, v) when is_float(u) and is_float(v) do
    :math.sqrt(u * u + v * v)
    |> Float.round(2)
  end

  defp wind_speed(_u, _v), do: "—"

  defp wind_direction(u, v) when is_float(u) and is_float(v) do
    rad = :math.atan2(u, v)
    deg = rad * 180.0 / :math.pi() + 180.0
    deg = rem(trunc(deg), 360)
    deg
  end

  defp wind_direction(_u, _v), do: "—"

  defp field_to_label(:measured_at), do: gettext("Timestamp")
  defp field_to_label(:value), do: gettext("Value")
  defp field_to_label(:u), do: gettext("u component")
  defp field_to_label(:v), do: gettext("v component")
  defp field_to_label(:gust), do: gettext("Gust")
  defp field_to_label(:interval_mm), do: gettext("Interval")
  defp field_to_label(:raw), do: gettext("Raw data")
  defp field_to_label(_), do: gettext("Field")
end
