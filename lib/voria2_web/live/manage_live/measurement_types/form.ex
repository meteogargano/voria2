defmodule Voria2Web.ManageLive.MeasurementTypes.Form do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(params, _session, socket) do
    socket = assign(socket, :active_section, :measurement_types)

    socket =
      case socket.assigns.live_action do
        :new ->
          form =
            AshPhoenix.Form.for_create(
              Voria2.Measurements.MeasurementType,
              :create,
              actor: socket.assigns.current_user
            )
            |> to_form()

          socket
          |> assign(:page_title, gettext("New Measurement Type"))
          |> assign(:form, form)
          |> assign(:measurement_type, nil)

        :edit ->
          id = params["id"]

          case Voria2.Measurements.get_measurement_type(id, actor: socket.assigns.current_user) do
            {:ok, type} ->
              form =
                AshPhoenix.Form.for_update(
                  type,
                  :update,
                  actor: socket.assigns.current_user
                )
                |> to_form()

              socket
              |> assign(:page_title, gettext("Edit %{name}", name: type.name))
              |> assign(:form, form)
              |> assign(:measurement_type, type)

            {:error, _} ->
              socket
              |> put_flash(:error, gettext("Measurement type not found."))
              |> push_navigate(to: ~p"/manage/measurement_types")
          end
      end

    {:ok, socket}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params) |> to_form()
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _type} ->
        message =
          if socket.assigns.live_action == :new,
            do: gettext("Measurement type created."),
            else: gettext("Measurement type updated.")

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/manage/measurement_types")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form |> to_form())}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <.breadcrumb crumbs={[
        {gettext("Measurement Types"), ~p"/manage/measurement_types"},
        {if(@live_action == :new, do: gettext("New Type"), else: @measurement_type.name), nil}
      ]} />

      <.header>
        {@page_title}
        <:subtitle :if={@live_action == :new}>
          {gettext("Define a new measurement category for your sensors.")}
        </:subtitle>
      </.header>

      <div class="mt-4">
        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class=" border border-base-300 bg-base-100 divide-y divide-base-300 overflow-hidden">
            <div class="px-6 py-4 bg-base-200/40">
              <h3 class="text-sm font-semibold">{gettext("Type Details")}</h3>
            </div>
            <div class="px-6 py-5 space-y-4">
              <.input
                field={@form[:name]}
                type="text"
                label={gettext("Name")}
                placeholder={gettext("Soil Moisture")}
              />
              <.input
                field={@form[:slug]}
                type="text"
                label={gettext("Slug")}
                placeholder={gettext("soil-moisture")}
                readonly={@live_action == :edit}
              />
              <.input
                field={@form[:storage_type]}
                type="select"
                label={gettext("Storage Type")}
                prompt={gettext("Select storage type...")}
                options={[
                  {gettext("Scalar (single value)"), "scalar"},
                  {gettext("Wind (u/v components)"), "wind"},
                  {gettext("Rain (precipitation)"), "rain"},
                  {gettext("Custom (flexible)"), "custom"}
                ]}
                readonly={@live_action == :edit}
              />
              <.input
                field={@form[:unit]}
                type="text"
                label={gettext("Unit")}
                placeholder={gettext("%, hPa, m/s, mm, etc.")}
              />
              <.input
                field={@form[:description]}
                type="textarea"
                label={gettext("Description")}
                placeholder={gettext("What this measurement type captures")}
                rows="3"
              />
              <.input field={@form[:is_active]} type="checkbox" label={gettext("Active")} />
            </div>
          </div>

          <div class="flex justify-end gap-3 mt-4">
            <.link navigate={~p"/manage/measurement_types"} class="btn btn-ghost btn-sm">
              {gettext("Cancel")}
            </.link>
            <.button type="submit" variant="primary">
              {if @live_action == :new, do: gettext("Create Type"), else: gettext("Save Changes")}
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
