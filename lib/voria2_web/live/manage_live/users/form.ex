defmodule Voria2Web.ManageLive.Users.Form do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(params, _session, socket) do
    unless socket.assigns.current_user.admin do
      {:ok,
       socket
       |> put_flash(:error, gettext("Admin access required."))
       |> push_navigate(to: ~p"/manage")}
    else
      socket = assign(socket, :active_section, :users)

      socket =
        case socket.assigns.live_action do
          :new ->
            form =
              AshPhoenix.Form.for_create(
                Voria2.Accounts.User,
                :register_with_password,
                actor: socket.assigns.current_user
              )
              |> to_form()

            socket
            |> assign(:page_title, gettext("New User"))
            |> assign(:form, form)
            |> assign(:user, nil)

          :edit ->
            id = params["id"]

            case Ash.get(Voria2.Accounts.User, id, authorize?: false) do
              {:ok, user} ->
                form =
                  AshPhoenix.Form.for_update(
                    user,
                    :update,
                    actor: socket.assigns.current_user
                  )
                  |> to_form()

                socket
                |> assign(:page_title, gettext("Edit %{name}", name: user.name))
                |> assign(:form, form)
                |> assign(:user, user)

              {:error, _} ->
                socket
                |> put_flash(:error, gettext("User not found."))
                |> push_navigate(to: ~p"/manage/users")
            end
        end

      {:ok, socket}
    end
  end

  def handle_event("delete_user", _params, socket) do
    case Voria2.Accounts.destroy_user(socket.assigns.user, actor: socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("User deleted."))
         |> push_navigate(to: ~p"/manage/users")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete user."))}
    end
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params) |> to_form()
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _} ->
        message =
          if socket.assigns.live_action == :new,
            do: gettext("User created successfully."),
            else: gettext("User updated.")

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/manage/users")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form |> to_form())}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <.breadcrumb crumbs={[
        {gettext("Users"), ~p"/manage/users"},
        {if(@live_action == :new,
           do: gettext("New User"),
           else: gettext("Edit %{name}", name: @user.name)
         ), nil}
      ]} />

      <.header>
        {@page_title}
        <:subtitle :if={@live_action == :new}>
          {gettext("Create a new account. The user can sign in immediately.")}
        </:subtitle>
      </.header>

      <div class="mt-4">
        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class=" border border-base-300 bg-base-100 divide-y divide-base-300 overflow-hidden">
            <div class="px-6 py-4 bg-base-200/40">
              <h3 class="text-sm font-semibold">{gettext("Account Details")}</h3>
            </div>
            <div class="px-6 py-5 space-y-4">
              <.input field={@form[:name]} type="text" label={gettext("Name")} placeholder="Jane Doe" />
              <.input
                field={@form[:email]}
                type="email"
                label={gettext("Email")}
                placeholder="jane@example.com"
              />

              <%!-- Password fields only on create --%>
              <div :if={@live_action == :new}>
                <.input
                  field={@form[:password]}
                  type="password"
                  label={gettext("Password")}
                  autocomplete="new-password"
                />
                <.input
                  field={@form[:password_confirmation]}
                  type="password"
                  label={gettext("Confirm Password")}
                  autocomplete="new-password"
                />
              </div>

              <%!-- Admin toggle only on edit --%>
              <.input
                :if={@live_action == :edit}
                field={@form[:admin]}
                type="checkbox"
                label={gettext("Admin")}
              />
            </div>
          </div>

          <div :if={@live_action == :edit} class="mt-3 px-1">
            <p class="text-xs text-base-content/40">
              {gettext("To change this user's password, use the password reset flow.")}
            </p>
          </div>

          <div class="flex justify-between gap-3 mt-4">
            <button
              :if={@live_action == :edit && @user.id != @current_user.id}
              type="button"
              class="btn btn-ghost btn-sm text-error hover:bg-error/10 gap-2"
              onclick="document.getElementById('del-user').showModal()"
            >
              <.icon name="hero-trash" class="size-4" /> {gettext("Delete User")}
            </button>
            <div class="flex gap-3 ml-auto">
              <.link navigate={~p"/manage/users"} class="btn btn-ghost btn-sm">
                {gettext("Cancel")}
              </.link>
              <.button type="submit" variant="primary">
                {if @live_action == :new, do: gettext("Create User"), else: gettext("Save Changes")}
              </.button>
            </div>
          </div>
        </.form>
      </div>

      <.confirm_modal
        :if={@live_action == :edit && @user.id != @current_user.id}
        id="del-user"
        title={gettext("Delete %{name}?", name: @user.name)}
        message={
          gettext("This will permanently delete the user account. This action cannot be undone.")
        }
        confirm_label={gettext("Delete User")}
        confirm_event="delete_user"
        confirm_value={%{}}
        danger={true}
      />
    </div>
    """
  end
end
