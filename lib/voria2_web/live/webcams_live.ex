defmodule Voria2Web.WebcamsLive do
  use Voria2Web, :live_view

  import Voria2Web.FlatpickrInputComponent

  on_mount {Voria2Web.LiveUserAuth, :live_user_optional}

  # ─── Mount ────────────────────────────────────────────────────────────────

  def mount(_params, _session, socket) do
    {:ok, webcam_data} = Voria2.Network.list_webcams_with_latest_shots_and_installations()

    socket =
      socket
      |> assign(:webcam_data, webcam_data)
      |> assign(:webcam, nil)
      |> assign(:installation, nil)
      |> assign(:shots, [])
      |> assign(:current_shot, nil)
      |> assign(:shot_url, nil)
      |> assign(:current_index, 0)
      |> assign(:viewing_date, Date.utc_today())
      |> assign(:jump_form, Voria2Web.WebcamJump.build_form(%{"webcam_id" => ""}))
      |> assign(:jump_error, nil)

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Voria2.PubSub, "webcam_shots")
        socket
      else
        socket
      end

    {:ok, socket}
  end

  # ─── Params ───────────────────────────────────────────────────────────────

  def handle_params(_params, _uri, %{assigns: %{live_action: :index}} = socket) do
    {:noreply,
     socket
     |> assign(:page_title, gettext("All Webcams"))
     |> assign(:webcam, nil)
     |> assign(:installation, nil)
     |> assign(:shots, [])
     |> assign(:current_shot, nil)
     |> assign(:shot_url, nil)
     |> assign(:current_index, 0)
     |> assign(:viewing_date, Date.utc_today())
     |> assign(:jump_form, Voria2Web.WebcamJump.build_form(%{"webcam_id" => ""}))
     |> assign(:jump_error, nil)}
  end

  def handle_params(%{"webcam_id" => webcam_id} = params, _uri, socket) do
    case Voria2.Network.get_webcam(webcam_id, authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Webcam not found."))
         |> push_patch(to: ~p"/webcams")}

      {:ok, webcam} ->
        case Voria2.Network.get_installation(webcam.installation_id, authorize?: false) do
          {:ok, installation} ->
            today = Date.utc_today()
            {shots, _} = Voria2Web.WebcamJump.load_shots_for_date(webcam_id, today)
            current_shot = List.first(shots)

            socket =
              socket
              |> assign(:webcam, webcam)
              |> assign(:installation, installation)
              |> assign(:shots, shots)
              |> assign(:current_shot, current_shot)
              |> assign(:shot_url, shot_url(current_shot))
              |> assign(:current_index, 0)
              |> assign(:viewing_date, today)
              |> assign(:jump_form, Voria2Web.WebcamJump.build_form())
              |> assign(:jump_error, nil)
              |> assign(:page_title, "#{webcam.name} — #{installation.name}")

            {:noreply, maybe_apply_jump_query(socket, webcam_id, params)}

          _ ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Webcam not found."))
             |> push_patch(to: ~p"/webcams")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Webcam not found."))
         |> push_patch(to: ~p"/webcams")}
    end
  end

  # ─── Render ───────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <.grid_view
        :if={@live_action == :index}
        webcam_data={@webcam_data}
        jump_form={@jump_form}
        jump_error={@jump_error}
      />
      <.viewer_view
        :if={@live_action == :show}
        webcam={@webcam}
        installation={@installation}
        shots={@shots}
        current_shot={@current_shot}
        shot_url={@shot_url}
        current_index={@current_index}
        viewing_date={@viewing_date}
        jump_form={@jump_form}
        jump_error={@jump_error}
      />
    </div>
    """
  end

  # ─── Grid View ────────────────────────────────────────────────────────────

  defp grid_view(assigns) do
    ~H"""
    <div class="public-subnav sticky z-20 border-b border-base-300 bg-base-100/95 py-3 backdrop-blur">
      <div class="mx-auto flex max-w-7xl flex-wrap items-center gap-3 px-4 sm:px-6 lg:px-8">
        <.link
          navigate={~p"/map"}
          class="btn btn-ghost btn-sm btn-circle"
          title={gettext("Back to map")}
        >
          <.icon name="hero-arrow-left" class="size-[18px]" />
        </.link>
        <div class="flex items-center gap-3">
          <h1 class="text-base font-bold">{gettext("All Webcams")}</h1>
          <span class="badge badge-neutral">{length(@webcam_data)}</span>
        </div>

        <.form
          for={@jump_form}
          id="webcams-grid-jump-form"
          phx-submit="jump_from_index"
          class="ml-auto grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-2 sm:w-auto sm:grid-cols-[auto_minmax(0,14rem)_auto]"
        >
          <select
            id="webcams-grid-jump-webcam"
            name="jump[webcam_id]"
            class="select select-sm select-bordered col-span-2 w-full sm:col-span-1 sm:w-44"
          >
            <option value="">{gettext("Select webcam")}</option>
            <option
              :for={entry <- @webcam_data}
              value={entry.webcam.id}
              selected={@jump_form[:webcam_id].value == entry.webcam.id}
            >
              {entry.webcam.name}
            </option>
          </select>
          <.datetime_picker
            id="webcams-grid-jump-input"
            field_name="jump[utc_iso]"
            display_name="jump[input]"
            value={@jump_form[:utc_iso].value}
            display_value={@jump_form[:input].value}
            submit_mode={:utc_iso}
            placeholder="dd/mm/yyyy hh:mm"
            minute_increment={1}
            force_custom_mobile={true}
            class="w-full sm:w-56"
          />
          <button
            type="submit"
            id="webcams-grid-jump-submit"
            class="btn btn-sm btn-primary btn-square shrink-0"
            aria-label={gettext("Search nearest shot")}
            title={gettext("Search nearest shot")}
          >
            <.icon name="hero-magnifying-glass" class="size-4" />
          </button>
        </.form>
      </div>

      <div :if={@jump_error} class="mx-auto mt-2 max-w-7xl px-4 sm:px-6 lg:px-8">
        <p id="webcams-grid-jump-error" class="text-sm text-error">{@jump_error}</p>
      </div>
    </div>
    <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <div :if={@webcam_data == []} class="text-center py-24 text-base-content/40">
        <p class="text-lg">{gettext("No webcams are currently active.")}</p>
      </div>

      <div :if={@webcam_data != []} class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <.webcam_card :for={entry <- @webcam_data} entry={entry} />
      </div>
    </div>
    """
  end

  defp webcam_card(assigns) do
    shot = assigns.entry.latest_shot
    url = shot && Voria2.Storage.public_url(shot.s3_key)
    assigns = assign(assigns, shot: shot, url: url)

    ~H"""
    <.link
      patch={~p"/webcams/#{@entry.webcam.id}"}
      class="card bg-base-200 border border-base-300 hover:border-primary transition-colors cursor-pointer overflow-hidden"
    >
      <figure class="aspect-video bg-base-300 overflow-hidden">
        <img
          :if={@url}
          src={@url}
          alt={@entry.webcam.name}
          class="w-full h-full object-cover"
          loading="lazy"
        />
        <div
          :if={!@url}
          class="w-full h-full flex items-center justify-center text-base-content/30 text-sm"
        >
          {gettext("No image")}
        </div>
      </figure>
      <div class="card-body p-3">
        <h3 class="font-semibold text-sm leading-tight">{@entry.webcam.name}</h3>
        <p class="text-xs text-base-content/60">{installation_name(@entry.installation)}</p>
        <p :if={@shot} class="text-xs text-base-content/50">
          <span
            id={"ts-wc-#{@entry.webcam.id}"}
            phx-hook="LocalTime"
            data-ts={DateTime.to_unix(@shot.captured_at, :millisecond)}
          >
            —
          </span>
        </p>
        <p :if={!@shot} class="text-xs text-base-content/40">{gettext("No shots yet")}</p>
      </div>
    </.link>
    """
  end

  # ─── Viewer View ──────────────────────────────────────────────────────────

  defp viewer_view(assigns) do
    ~H"""
    <div>
      <%!-- Header --%>
      <div class="public-subnav sticky z-20 border-b border-base-300 bg-base-100/95 py-3 backdrop-blur">
        <div class="mx-auto flex max-w-7xl items-center gap-3 px-4 sm:px-6 lg:px-8">
          <.link
            patch={~p"/webcams"}
            class="btn btn-ghost btn-sm btn-circle"
            title={gettext("Back to all webcams")}
          >
            <.icon name="hero-arrow-left" class="size-[18px]" />
          </.link>
          <div class="flex-1 min-w-0">
            <h1 class="text-base font-bold leading-tight truncate">{@webcam.name}</h1>
            <p class="text-xs text-base-content/50 truncate">{@installation.name}</p>
          </div>
          <div :if={@webcam.stream_url} class="hidden sm:block">
            <a href={@webcam.stream_url} target="_blank" class="btn btn-ghost btn-sm gap-1">
              {gettext("Live Stream ↗")}
            </a>
          </div>
        </div>
      </div>

      <div class="mx-auto max-w-7xl space-y-4 px-4 py-6 sm:px-6 lg:px-8">
        <%!-- Image display --%>
        <div class="relative bg-base-300 overflow-hidden">
          <img
            :if={@shot_url}
            id="webcams-shot-image"
            src={@shot_url}
            alt={@webcam.name}
            class="block w-full h-auto max-h-[70vh] object-contain"
          />
          <div :if={!@shot_url} class="flex items-center justify-center h-72 text-base-content/30">
            {gettext("No image available")}
          </div>
        </div>

        <%!-- Navigation controls --%>
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-4">
            <div class="flex flex-wrap items-center gap-3">
              <%!-- Shot counter --%>
              <span class="text-sm text-base-content/60 min-w-fit">
                {if @shots == [],
                  do: gettext("No shots"),
                  else: "#{@current_index + 1} / #{length(@shots)}"}
              </span>

              <%!-- Prev / Next --%>
              <div class="flex gap-2">
                <button
                  phx-click="prev_shot"
                  disabled={@shots == [] or @current_index >= length(@shots) - 1}
                  class="btn btn-sm btn-ghost gap-1"
                >
                  ‹ {gettext("Prev")}
                </button>
                <button
                  phx-click="next_shot"
                  disabled={@shots == [] or @current_index <= 0}
                  class="btn btn-sm btn-ghost gap-1"
                >
                  {gettext("Next")} ›
                </button>
              </div>

              <%!-- Latest --%>
              <button
                phx-click="go_latest"
                class="btn btn-sm btn-ghost"
                disabled={@shots == [] or @current_index == 0}
              >
                {gettext("Latest")}
              </button>

              <.form
                for={@jump_form}
                id="webcams-jump-form"
                phx-submit="jump_to_datetime"
                class="ml-auto grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-2 sm:w-auto sm:grid-cols-[minmax(0,14rem)_auto]"
              >
                <.datetime_picker
                  id="webcams-jump-input"
                  field_name="jump[utc_iso]"
                  display_name="jump[input]"
                  value={@jump_form[:utc_iso].value}
                  display_value={@jump_form[:input].value}
                  submit_mode={:utc_iso}
                  placeholder="dd/mm/yyyy hh:mm"
                  minute_increment={1}
                  force_custom_mobile={true}
                  class="w-full sm:w-56"
                />
                <button
                  type="submit"
                  id="webcams-jump-submit"
                  class="btn btn-sm btn-primary btn-square shrink-0"
                  aria-label={gettext("Search nearest shot")}
                  title={gettext("Search nearest shot")}
                >
                  <.icon name="hero-magnifying-glass" class="size-4" />
                </button>
              </.form>
            </div>

            <p :if={@jump_error} id="webcams-jump-error" class="text-sm text-error mt-2">
              {@jump_error}
            </p>

            <%!-- Shot metadata --%>
            <div
              :if={@current_shot}
              class="flex flex-wrap gap-x-6 gap-y-1 text-xs text-base-content/60 border-t border-base-300 pt-3 mt-1"
            >
              <span>
                <strong class="text-base-content">{gettext("Captured:")}</strong>
                <span
                  id="ts-viewer-captured"
                  phx-hook="LocalTime"
                  data-ts={DateTime.to_unix(@current_shot.captured_at, :millisecond)}
                  data-format="datetime-sec"
                >
                  —
                </span>
              </span>
              <span :if={@current_shot.width && @current_shot.height}>
                <strong class="text-base-content">{gettext("Size:")}</strong>
                {@current_shot.width}×{@current_shot.height}
              </span>
              <span :if={@current_shot.file_size_bytes}>
                <strong class="text-base-content">{gettext("File:")}</strong>
                {format_bytes(@current_shot.file_size_bytes)}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ─── Events ───────────────────────────────────────────────────────────────

  def handle_event("prev_shot", _, socket) do
    idx = min(socket.assigns.current_index + 1, length(socket.assigns.shots) - 1)
    {:noreply, set_shot_index(socket, idx)}
  end

  def handle_event("next_shot", _, socket) do
    idx = max(socket.assigns.current_index - 1, 0)
    {:noreply, set_shot_index(socket, idx)}
  end

  def handle_event("go_latest", _, socket) do
    {:noreply, set_shot_index(socket, 0)}
  end

  def handle_event("jump_from_index", %{"jump" => params}, socket) do
    webcam_id = Map.get(params, "webcam_id", "")

    cond do
      webcam_id == "" ->
        {:noreply,
         socket
         |> assign(:jump_form, Voria2Web.WebcamJump.build_form(params))
         |> assign(:jump_error, gettext("Select a webcam first."))}

      true ->
        {:noreply,
         socket
         |> assign(:jump_form, Voria2Web.WebcamJump.build_form(params))
         |> assign(:jump_error, nil)
         |> push_patch(
           to:
             ~p"/webcams/#{webcam_id}?#{%{jump_input: params["input"], utc_iso: params["utc_iso"]}}"
         )}
    end
  end

  def handle_event("jump_to_datetime", %{"jump" => params}, socket) do
    case Voria2Web.WebcamJump.jump_to_datetime(socket.assigns.webcam.id, params) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:shots, result.shots)
         |> assign(:current_shot, result.current_shot)
         |> assign(:shot_url, shot_url(result.current_shot))
         |> assign(:current_index, result.current_index)
         |> assign(:viewing_date, result.viewing_date)
         |> assign(:jump_form, result.form)
         |> assign(:jump_error, nil)}

      {:error, result} ->
        {:noreply,
         socket
         |> assign(:jump_form, result.form)
         |> assign(:jump_error, result.error)}
    end
  end

  # ─── PubSub ───────────────────────────────────────────────────────────────

  def handle_info({:new_webcam_shot, %{webcam_id: wid}}, socket) do
    {:ok, shot} = Voria2.Cache.latest_shot_for_webcam(wid)

    updated_grid =
      Enum.map(socket.assigns.webcam_data, fn entry ->
        if entry.webcam.id == wid, do: %{entry | latest_shot: shot}, else: entry
      end)

    socket = assign(socket, :webcam_data, updated_grid)

    socket =
      if ((socket.assigns.live_action == :show and
             socket.assigns.webcam) && socket.assigns.webcam.id == wid) and
           shot do
        today = Date.utc_today()

        if socket.assigns.viewing_date == today do
          updated_shots = [shot | Enum.reject(socket.assigns.shots, &(&1.id == shot.id))]

          socket
          |> assign(:shots, updated_shots)
          |> assign(:current_shot, shot)
          |> assign(:shot_url, shot_url(shot))
          |> assign(:current_index, 0)
        else
          socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ─── Helpers ──────────────────────────────────────────────────────────────

  defp set_shot_index(socket, idx) do
    shot = Enum.at(socket.assigns.shots, idx)

    socket
    |> assign(:current_index, idx)
    |> assign(:current_shot, shot)
    |> assign(:shot_url, shot_url(shot))
  end

  defp shot_url(nil), do: nil
  defp shot_url(shot), do: Voria2.Storage.public_url(shot.s3_key)

  defp maybe_apply_jump_query(socket, webcam_id, %{"jump_input" => input, "utc_iso" => utc_iso}) do
    case Voria2Web.WebcamJump.jump_to_datetime(webcam_id, %{
           "input" => input,
           "utc_iso" => utc_iso
         }) do
      {:ok, result} ->
        socket
        |> assign(:shots, result.shots)
        |> assign(:current_shot, result.current_shot)
        |> assign(:shot_url, shot_url(result.current_shot))
        |> assign(:current_index, result.current_index)
        |> assign(:viewing_date, result.viewing_date)
        |> assign(:jump_form, result.form)
        |> assign(:jump_error, nil)

      {:error, result} ->
        socket
        |> assign(:jump_form, result.form)
        |> assign(:jump_error, result.error)
    end
  end

  defp maybe_apply_jump_query(socket, _webcam_id, _params), do: socket

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp installation_name(nil), do: gettext("Unknown installation")
  defp installation_name(inst), do: inst.name
end
