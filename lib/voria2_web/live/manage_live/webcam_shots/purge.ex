defmodule Voria2Web.ManageLive.WebcamShots.Purge do
  use Voria2Web, :live_view

  import Voria2Web.FlatpickrInputComponent

  alias Voria2.Network.WebcamShotPurger

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  @default_preset :h24
  @presets [h1: "1h", h6: "6h", h24: "24h", d7: "7d", d30: "30d"]

  @impl true
  def mount(_params, _session, socket) do
    unless socket.assigns.current_user.admin do
      {:ok,
       socket
       |> put_flash(:error, gettext("Admin access required."))
       |> push_navigate(to: ~p"/manage")}
    else
      {from, to} = preset_window(@default_preset, DateTime.utc_now())

      socket =
        socket
        |> assign(:page_title, gettext("Webcam Shot Purge"))
        |> assign(:active_section, :webcam_shots)
        |> assign(:webcams, list_webcams(socket.assigns.current_user))
        |> assign(:presets, @presets)
        |> assign(:search_query, "")
        |> assign(:selected_webcam_ids, MapSet.new())
        |> assign(:filter_form, build_filter_form(from, to))
        |> assign(:filter_error, nil)
        |> assign(:matched_count, nil)
        |> assign(:active_preset, @default_preset)
        |> assign(:purge_status, WebcamShotPurger.snapshot())

      socket =
        if connected?(socket) do
          WebcamShotPurger.subscribe()
          assign(socket, :purge_status, WebcamShotPurger.snapshot())
        else
          socket
        end

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("search_webcams", %{"value" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  def handle_event("toggle_webcam", %{"id" => webcam_id}, socket) do
    selected_webcam_ids =
      if MapSet.member?(socket.assigns.selected_webcam_ids, webcam_id) do
        MapSet.delete(socket.assigns.selected_webcam_ids, webcam_id)
      else
        MapSet.put(socket.assigns.selected_webcam_ids, webcam_id)
      end

    {:noreply,
     socket
     |> assign(:selected_webcam_ids, selected_webcam_ids)
     |> assign(:matched_count, nil)}
  end

  def handle_event("update_filters", %{"filters" => params}, socket) do
    {:noreply,
     socket
     |> assign(:filter_form, build_filter_form(params))
     |> assign(:filter_error, nil)
     |> assign(:matched_count, nil)
     |> assign(:active_preset, nil)}
  end

  def handle_event("apply_preset", %{"preset" => preset_name}, socket) do
    preset = parse_preset(preset_name)
    {from, to} = preset_window(preset, DateTime.utc_now())

    {:noreply,
     socket
     |> assign(:filter_form, build_filter_form(from, to))
     |> assign(:filter_error, nil)
     |> assign(:matched_count, nil)
     |> assign(:active_preset, preset)}
  end

  def handle_event("preview_count", %{"filters" => params}, socket) do
    socket = assign(socket, :filter_form, build_filter_form(params))

    case resolve_filters(socket.assigns.selected_webcam_ids, params) do
      {:ok, filters} ->
        matched_count =
          Voria2.Network.count_webcam_shots_in_range!(
            filters.webcam_ids,
            filters.from,
            filters.to
          )

        {:noreply,
         socket
         |> assign(:filter_error, nil)
         |> assign(:matched_count, matched_count)}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:matched_count, nil)
         |> assign(:filter_error, message)}
    end
  end

  def handle_event("start_purge", %{"filters" => params}, socket) do
    socket = assign(socket, :filter_form, build_filter_form(params))

    with {:ok, filters} <- resolve_filters(socket.assigns.selected_webcam_ids, params),
         {:ok, snapshot} <- WebcamShotPurger.start_purge(socket.assigns.current_user, filters) do
      {:noreply,
       socket
       |> assign(:filter_error, nil)
       |> assign(:matched_count, snapshot.total)
       |> assign(:purge_status, snapshot)
       |> put_flash(:info, gettext("Webcam shot purge started."))}
    else
      {:error, :already_running} ->
        {:noreply,
         socket
         |> assign(:purge_status, WebcamShotPurger.snapshot())
         |> put_flash(:error, gettext("A webcam shot purge is already running."))}

      {:error, message} when is_binary(message) ->
        {:noreply,
         socket
         |> assign(:filter_error, message)
         |> put_flash(:error, message)}
    end
  end

  @impl true
  def handle_info({:webcam_shot_purger, snapshot}, socket) do
    {:noreply, assign(socket, :purge_status, snapshot)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl">
      <.breadcrumb crumbs={[{gettext("Webcam Shot Purge"), nil}]} />

      <.header>
        {gettext("Webcam Shot Purge")}
        <:subtitle>
          {gettext(
            "Select webcams, choose a local date range, count matching shots, then purge them from storage and the database in monitored batches."
          )}
        </:subtitle>
      </.header>

      <div class="mt-4 space-y-6">
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-5 gap-4">
            <div class="flex items-center justify-between gap-3 flex-wrap">
              <div>
                <h2 class="text-base font-semibold">{gettext("Webcams")}</h2>
                <p class="text-sm text-base-content/60">
                  {gettext("%{count} selected", count: MapSet.size(@selected_webcam_ids))}
                </p>
              </div>

              <label class="input input-sm input-bordered flex items-center gap-2 w-full sm:w-72">
                <.icon name="hero-magnifying-glass" class="size-4 text-base-content/40" />
                <input
                  id="webcam-shot-purge-search"
                  type="text"
                  value={@search_query}
                  placeholder={gettext("Search webcams...")}
                  phx-change="search_webcams"
                />
              </label>
            </div>

            <div
              id="webcam-shot-purge-webcams"
              class="max-h-72 overflow-y-auto divide-y divide-base-300 border border-base-300 bg-base-100"
            >
              <label
                :for={webcam <- filtered_webcams(@webcams, @search_query)}
                class="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-base-200/70 transition-colors"
              >
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  checked={MapSet.member?(@selected_webcam_ids, webcam.id)}
                  phx-click="toggle_webcam"
                  phx-value-id={webcam.id}
                />
                <div class="min-w-0 flex-1">
                  <div class="font-medium text-sm truncate">{webcam.name}</div>
                  <div class="text-xs text-base-content/50 truncate">
                    {webcam.installation.name}
                    <%= if installation_location(webcam.installation) != "" do %>
                      {", " <> installation_location(webcam.installation)}
                    <% end %>
                  </div>
                </div>
              </label>

              <div
                :if={filtered_webcams(@webcams, @search_query) == []}
                class="px-4 py-8 text-sm text-base-content/50 text-center"
              >
                {gettext("No webcams match your search.")}
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-5 gap-4">
            <div>
              <h2 class="text-base font-semibold">{gettext("Date Range")}</h2>
            </div>

            <.form
              for={@filter_form}
              id="webcam-shot-purge-form"
              phx-change="update_filters"
              phx-submit="preview_count"
              class="space-y-4"
            >
              <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <fieldset>
                  <.datetime_picker
                    id="webcam-shot-purge-from"
                    field_name="filters[from_utc_iso]"
                    display_name="filters[from_input]"
                    value={@filter_form[:from_utc_iso].value}
                    display_value={@filter_form[:from_input].value}
                    submit_mode={:utc_iso}
                    label={gettext("Start")}
                    placeholder="dd/mm/yyyy hh:mm"
                    minute_increment={1}
                    force_custom_mobile={true}
                  />
                </fieldset>

                <fieldset>
                  <.datetime_picker
                    id="webcam-shot-purge-to"
                    field_name="filters[to_utc_iso]"
                    display_name="filters[to_input]"
                    value={@filter_form[:to_utc_iso].value}
                    display_value={@filter_form[:to_input].value}
                    submit_mode={:utc_iso}
                    label={gettext("End")}
                    placeholder="dd/mm/yyyy hh:mm"
                    minute_increment={1}
                    force_custom_mobile={true}
                  />
                </fieldset>
              </div>

              <div class="flex flex-wrap items-center gap-2">
                <span class="text-xs font-semibold uppercase tracking-wide text-base-content/40">
                  {gettext("Presets")}
                </span>
                <button
                  :for={{preset, label} <- @presets}
                  type="button"
                  phx-click="apply_preset"
                  phx-value-preset={preset}
                  class={[
                    "btn btn-xs",
                    @active_preset == preset && "btn-primary",
                    @active_preset != preset && "btn-ghost"
                  ]}
                >
                  {label}
                </button>
              </div>

              <p :if={@filter_error} id="webcam-shot-purge-error" class="text-sm text-error">
                {@filter_error}
              </p>

              <div class="flex flex-wrap items-center gap-3 justify-between border border-base-300 bg-base-100 px-4 py-3">
                <div>
                  <div class="text-xs uppercase tracking-wide text-base-content/40">
                    {gettext("Matched shots")}
                  </div>
                  <div id="webcam-shot-purge-count" class="text-2xl font-semibold">
                    {format_count(@matched_count)}
                  </div>
                </div>

                <div class="flex flex-wrap gap-2">
                  <button
                    type="submit"
                    id="webcam-shot-purge-preview"
                    class="btn btn-primary btn-sm gap-2"
                    disabled={
                      MapSet.size(@selected_webcam_ids) == 0 or @purge_status.status == :running
                    }
                  >
                    <.icon name="hero-magnifying-glass" class="size-4" /> {gettext("Count Shots")}
                  </button>

                  <button
                    type="button"
                    id="webcam-shot-purge-start"
                    class="btn btn-error btn-sm gap-2"
                    disabled={
                      MapSet.size(@selected_webcam_ids) == 0 or @purge_status.status == :running
                    }
                    onclick="document.getElementById('webcam-shot-purge-confirm').showModal()"
                  >
                    <.icon name="hero-trash" class="size-4" /> {gettext("Start Purge")}
                  </button>
                </div>
              </div>
            </.form>
          </div>
        </div>

        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-5 gap-4">
            <div class="flex items-center justify-between gap-3 flex-wrap">
              <div>
                <h2 class="text-base font-semibold">{gettext("Live Monitor")}</h2>
                <p class="text-sm text-base-content/60">
                  {gettext("Only one purge job can run at a time.")}
                </p>
              </div>

              <span id="purge-status" class={status_badge_classes(@purge_status.status)}>
                {format_status(@purge_status.status)}
              </span>
            </div>

            <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
              <.metric_card id="purge-total" label={gettext("Total")} value={@purge_status.total} />
              <.metric_card
                id="purge-processed"
                label={gettext("Processed")}
                value={@purge_status.processed}
              />
              <.metric_card
                id="purge-deleted"
                label={gettext("Deleted")}
                value={@purge_status.deleted}
              />
              <.metric_card id="purge-failed" label={gettext("Failed")} value={@purge_status.failed} />
            </div>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-3 text-sm">
              <div class="border border-base-300 bg-base-100 px-4 py-3">
                <div class="text-xs uppercase tracking-wide text-base-content/40">
                  {gettext("Current batch")}
                </div>
                <div id="purge-current-batch" class="font-semibold mt-1">
                  {@purge_status.current_batch_size}
                </div>
              </div>
              <div class="border border-base-300 bg-base-100 px-4 py-3">
                <div class="text-xs uppercase tracking-wide text-base-content/40">
                  {gettext("Batches completed")}
                </div>
                <div id="purge-batches" class="font-semibold mt-1">
                  {@purge_status.batches_completed}
                </div>
              </div>
              <div class="border border-base-300 bg-base-100 px-4 py-3">
                <div class="text-xs uppercase tracking-wide text-base-content/40">
                  {gettext("Range")}
                </div>
                <div id="purge-range" class="font-semibold mt-1">
                  {purge_range_label(@purge_status)}
                </div>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
              <div class="border border-base-300 bg-base-100 px-4 py-3">
                <div class="text-xs uppercase tracking-wide text-base-content/40">
                  {gettext("Started")}
                </div>
                <div id="purge-started-at" class="font-semibold mt-1">
                  {format_datetime(@purge_status.started_at)}
                </div>
              </div>
              <div class="border border-base-300 bg-base-100 px-4 py-3">
                <div class="text-xs uppercase tracking-wide text-base-content/40">
                  {gettext("Finished")}
                </div>
                <div id="purge-finished-at" class="font-semibold mt-1">
                  {format_datetime(@purge_status.finished_at)}
                </div>
              </div>
            </div>

            <div class="border border-base-300 bg-base-100 px-4 py-3">
              <div class="text-xs uppercase tracking-wide text-base-content/40 mb-2">
                {gettext("Recent errors")}
              </div>
              <div id="purge-errors" class="space-y-2">
                <p :if={@purge_status.recent_errors == []} class="text-sm text-base-content/50">
                  {gettext("No errors recorded.")}
                </p>
                <p
                  :for={error <- @purge_status.recent_errors}
                  class="text-sm font-mono break-all text-error"
                >
                  {error}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <dialog id="webcam-shot-purge-confirm" class="modal modal-bottom sm:modal-middle">
        <div class="modal-box">
          <h3 class="font-semibold text-lg">{gettext("Start webcam shot purge?")}</h3>
          <p class="py-4 text-sm text-base-content/70">
            {gettext(
              "This will delete matching webcam shots from storage first and then from the database."
            )}
          </p>
          <div class="modal-action gap-2">
            <form method="dialog">
              <button class="btn btn-ghost btn-sm">{gettext("Cancel")}</button>
            </form>

            <.form for={@filter_form} id="webcam-shot-purge-confirm-form" phx-submit="start_purge">
              <input type="hidden" name="filters[from_input]" value={@filter_form[:from_input].value} />
              <input
                type="hidden"
                name="filters[from_utc_iso]"
                value={@filter_form[:from_utc_iso].value}
              />
              <input type="hidden" name="filters[to_input]" value={@filter_form[:to_input].value} />
              <input
                type="hidden"
                name="filters[to_utc_iso]"
                value={@filter_form[:to_utc_iso].value}
              />
              <button class="btn btn-error btn-sm" type="submit">{gettext("Start Purge")}</button>
            </.form>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button>close</button>
        </form>
      </dialog>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, default: 0

  defp metric_card(assigns) do
    ~H"""
    <div class="border border-base-300 bg-base-100 px-4 py-3">
      <div class="text-xs uppercase tracking-wide text-base-content/40">{@label}</div>
      <div id={@id} class="text-xl font-semibold mt-1">{@value}</div>
    </div>
    """
  end

  defp list_webcams(actor) do
    Voria2.Network.Webcam
    |> Ash.Query.load(:installation)
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: actor, authorize?: false)
  end

  defp filtered_webcams(webcams, query) do
    normalized_query = String.downcase(String.trim(query || ""))

    if normalized_query == "" do
      webcams
    else
      Enum.filter(webcams, fn webcam ->
        haystack =
          [
            webcam.name,
            webcam.installation.name,
            webcam.installation.city,
            webcam.installation.country
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" ")
          |> String.downcase()

        String.contains?(haystack, normalized_query)
      end)
    end
  end

  defp installation_location(installation) do
    [installation.city, installation.country]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp build_filter_form(%{} = params) do
    Phoenix.Component.to_form(
      %{
        "from_input" => Map.get(params, "from_input", ""),
        "from_utc_iso" => Map.get(params, "from_utc_iso", ""),
        "to_input" => Map.get(params, "to_input", ""),
        "to_utc_iso" => Map.get(params, "to_utc_iso", "")
      },
      as: :filters
    )
  end

  defp build_filter_form(%DateTime{} = from, %DateTime{} = to) do
    build_filter_form(%{
      "from_input" => Calendar.strftime(from, "%d/%m/%Y %H:%M"),
      "from_utc_iso" => DateTime.to_iso8601(from),
      "to_input" => Calendar.strftime(to, "%d/%m/%Y %H:%M"),
      "to_utc_iso" => DateTime.to_iso8601(to)
    })
  end

  defp resolve_filters(selected_webcam_ids, params) do
    webcam_ids = MapSet.to_list(selected_webcam_ids)

    cond do
      webcam_ids == [] ->
        {:error, gettext("Select at least one webcam.")}

      true ->
        with {:ok, from} <- parse_filter_datetime(Map.get(params, "from_utc_iso")),
             {:ok, to} <- parse_filter_datetime(Map.get(params, "to_utc_iso")),
             :ok <- validate_filter_range(from, to) do
          {:ok, %{webcam_ids: webcam_ids, from: from, to: to}}
        end
    end
  end

  defp parse_filter_datetime(nil), do: {:error, gettext("Enter both start and end datetimes.")}
  defp parse_filter_datetime(""), do: {:error, gettext("Enter both start and end datetimes.")}

  defp parse_filter_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, gettext("Enter both start and end datetimes.")}
    end
  end

  defp validate_filter_range(from, to) do
    case DateTime.compare(from, to) do
      :gt -> {:error, gettext("Start must be before end.")}
      _ -> :ok
    end
  end

  defp parse_preset(preset_name) do
    preset_name
    |> String.to_existing_atom()
  rescue
    ArgumentError -> @default_preset
  end

  defp preset_window(:h1, now), do: {DateTime.add(now, -3_600, :second), now}
  defp preset_window(:h6, now), do: {DateTime.add(now, -6 * 3_600, :second), now}
  defp preset_window(:h24, now), do: {DateTime.add(now, -24 * 3_600, :second), now}
  defp preset_window(:d7, now), do: {DateTime.add(now, -7 * 24 * 3_600, :second), now}
  defp preset_window(:d30, now), do: {DateTime.add(now, -30 * 24 * 3_600, :second), now}

  defp format_count(nil), do: "—"
  defp format_count(value), do: Integer.to_string(value)

  defp format_status(:idle), do: gettext("Idle")
  defp format_status(:running), do: gettext("Running")
  defp format_status(:completed), do: gettext("Completed")
  defp format_status(:failed), do: gettext("Failed")

  defp status_badge_classes(:idle), do: "badge badge-neutral"
  defp status_badge_classes(:running), do: "badge badge-info"
  defp status_badge_classes(:completed), do: "badge badge-success"
  defp status_badge_classes(:failed), do: "badge badge-error"

  defp purge_range_label(%{from: nil, to: nil}), do: "—"

  defp purge_range_label(%{from: from, to: to}) do
    "#{format_datetime(from)} -> #{format_datetime(to)}"
  end

  defp format_datetime(nil), do: "—"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%d/%m/%Y %H:%M")
end
