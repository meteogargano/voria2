defmodule Voria2Web.WebcamViewerLive do
  use Voria2Web, :live_view

  import Voria2Web.FlatpickrInputComponent

  on_mount {Voria2Web.LiveUserAuth, :live_user_optional}

  # ─── Mount ────────────────────────────────────────────────────────────────

  def mount(%{"webcam_id" => webcam_id}, _session, socket) do
    case Voria2.Network.get_webcam(webcam_id, authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Webcam not found."))
         |> push_navigate(to: ~p"/map")}

      {:ok, webcam} ->
        installation =
          Ash.get!(Voria2.Network.Installation, webcam.installation_id, authorize?: false)

        today = Date.utc_today()
        {shots, _date} = Voria2Web.WebcamJump.load_shots_for_date(webcam_id, today)
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

        socket =
          if connected?(socket) do
            Phoenix.PubSub.subscribe(Voria2.PubSub, "webcam_shots")
            socket
          else
            socket
          end

        {:ok, socket}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Webcam not found."))
         |> push_navigate(to: ~p"/map")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # ─── Render ───────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <%!-- Header --%>
      <div class="public-subnav sticky z-20 border-b border-base-300 bg-base-100/95 py-3 backdrop-blur">
        <div class="mx-auto flex max-w-7xl items-center gap-3 px-4 sm:px-6 lg:px-8">
          <.link
            navigate={~p"/installations/#{@installation.id}?tab=webcams"}
            class="btn btn-ghost btn-sm btn-circle"
            title={gettext("Back to installation")}
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
            id="webcam-shot-image"
            src={@shot_url}
            alt={@webcam.name}
            class="w-full h-auto max-h-[70vh] object-contain"
          />
          <div
            :if={!@shot_url}
            class="flex items-center justify-center h-48 sm:h-72 text-base-content/30"
          >
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
                id="webcam-jump-form"
                phx-submit="jump_to_datetime"
                class="ml-auto grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-2 sm:w-auto sm:grid-cols-[minmax(0,14rem)_auto]"
              >
                <.datetime_picker
                  id="webcam-jump-input"
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
                  id="webcam-jump-submit"
                  class="btn btn-sm btn-primary btn-square shrink-0"
                  aria-label={gettext("Search nearest shot")}
                  title={gettext("Search nearest shot")}
                >
                  <.icon name="hero-magnifying-glass" class="size-4" />
                </button>
              </.form>
            </div>

            <p :if={@jump_error} id="webcam-jump-error" class="text-sm text-error mt-2">
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
                  id="ts-shot-captured"
                  phx-hook="LocalTime"
                  data-ts={DateTime.to_unix(@current_shot.captured_at, :millisecond)}
                  data-format="datetime-sec"
                >
                  —
                </span>
              </span>
              <span :if={@current_shot.width && @current_shot.height}>
                <strong class="text-base-content">{gettext("Size:")}</strong> {@current_shot.width}×{@current_shot.height}
              </span>
              <span :if={@current_shot.file_size_bytes}>
                <strong class="text-base-content">{gettext("File:")}</strong> {format_bytes(
                  @current_shot.file_size_bytes
                )}
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
    if wid == socket.assigns.webcam.id do
      {:ok, shot} = Voria2.Cache.latest_shot_for_webcam(wid)

      if shot do
        # Only prepend to the list if viewing today's date
        today = Date.utc_today()

        socket =
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

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
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

  defp format_bytes(nil), do: "—"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
