defmodule Voria2Web.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use Voria2Web, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_path, :string, default: nil

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col bg-base-100 text-base-content">
      <.public_navbar current_path={assigns[:current_path]} />

      <main class="flex-1">
        {render_slot(@inner_block)}
      </main>

      <.public_footer />

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :logo_class, :string, default: nil
  attr :title_class, :string, default: nil
  attr :subtitle_class, :string, default: nil
  slot :inner_block, required: true

  defp brand_block(assigns) do
    ~H"""
    <div class="flex items-center gap-3 min-w-0">
      <div class={["shrink-0", @logo_class]}>
        <img
          src={~p"/images/app-logo.svg"}
          alt="MeteoGargano logo"
          class="block size-full object-contain"
        />
      </div>
      <div class="hidden min-w-0 md:block">
        <p class={[
          "truncate font-semibold uppercase tracking-[0.1em] text-base-content/45",
          @title_class
        ]}>
          Associazione
        </p>
        <p class={[
          "truncate font-semibold leading-tight text-base-content/75",
          @subtitle_class
        ]}>
          {render_slot(@inner_block)}
        </p>
      </div>
    </div>
    """
  end

  def public(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col bg-base-100 text-base-content">
      <.public_navbar current_path={assigns[:current_path] || conn_path(@conn)} />

      <main class="flex-1">
        {@inner_content}
      </main>

      <.public_footer />

      <.flash_group flash={assigns[:flash] || %{}} />
    </div>
    """
  end

  attr :current_path, :string, default: nil

  defp public_navbar(assigns) do
    assigns =
      assign(assigns,
        home_active?: nav_active?(assigns.current_path, :home),
        map_active?: nav_active?(assigns.current_path, :map),
        map_page_active?: nav_active?(assigns.current_path, :map_page),
        compare_active?: nav_active?(assigns.current_path, :compare),
        webcams_active?: nav_active?(assigns.current_path, :webcams),
        preferences_active?: nav_active?(assigns.current_path, :preferences),
        blog_active?: nav_active?(assigns.current_path, :blog),
        associazione_active?: nav_active?(assigns.current_path, :associazione)
      )

    ~H"""
    <header class="sticky top-0 z-[1100] border-b border-base-300 bg-base-100/95 backdrop-blur">
      <div class="mx-auto flex min-h-[3.75rem] max-w-7xl items-center justify-between gap-6 px-4 sm:px-6 lg:px-8">
        <.link href={~p"/"} class="flex items-center gap-3">
          <.brand_block
            logo_class="size-9"
            title_class="text-[10px]"
            subtitle_class="text-xs sm:text-sm"
          >
            MeteoGargano
          </.brand_block>
        </.link>

        <nav class="flex items-center gap-4 sm:gap-6">
          <.public_nav_link
            href={~p"/"}
            label={gettext("Home")}
            active={@home_active?}
            class="hidden md:inline-flex"
          />
          <.public_nav_link
            href={~p"/associazione"}
            label={gettext("Associazione")}
            active={@associazione_active?}
          />
          <.public_nav_link href={~p"/blog"} label={gettext("Blog")} active={@blog_active?} />
          <.public_nav_dropdown label={gettext("Rete Meteo")} active={@map_active?}>
            <:item
              href={~p"/map"}
              label={gettext("Rete Meteo")}
              icon="hero-map"
              active={@map_page_active?}
            />
            <:item
              href={~p"/compare"}
              label={gettext("Compare")}
              icon="hero-chart-bar"
              active={@compare_active?}
            />
            <:item
              href={~p"/webcams"}
              label={gettext("All Webcams")}
              icon="hero-video-camera"
              active={@webcams_active?}
            />
          </.public_nav_dropdown>
          <.public_nav_icon_link
            href={~p"/preferences"}
            label={gettext("Preferences")}
            icon="hero-cog-6-tooth"
            active={@preferences_active?}
            class="-ml-2 sm:-ml-3"
          />
        </nav>
      </div>
    </header>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :class, :string, default: nil

  defp public_nav_link(assigns) do
    ~H"""
    <.link
      href={@href}
      class={[
        @class,
        "relative py-2 text-sm font-medium transition",
        @active && "text-base-content",
        !@active && "text-base-content/65 hover:text-base-content"
      ]}
      aria-current={if @active, do: "page", else: nil}
    >
      {@label}

      <span class={[
        "absolute inset-x-0 -bottom-px h-0.5 transition",
        @active && "bg-primary",
        !@active && "bg-transparent"
      ]}>
      </span>
    </.link>
    """
  end

  attr :label, :string, required: true
  attr :active, :boolean, default: false

  slot :item, required: true do
    attr :href, :string, required: true
    attr :label, :string, required: true
    attr :icon, :string, required: true
    attr :active, :boolean
  end

  defp public_nav_dropdown(assigns) do
    ~H"""
    <div class="dropdown dropdown-end" id="nav-rete-meteo-dropdown">
      <div
        tabindex="0"
        role="button"
        aria-haspopup="menu"
        aria-label={@label}
        class={[
          "relative flex cursor-pointer select-none items-center gap-1.5 py-2 text-sm font-medium transition",
          @active && "text-base-content",
          !@active && "text-base-content/65 hover:text-base-content"
        ]}
      >
        {@label}
        <.icon name="hero-chevron-down" class="nav-dropdown-chevron size-3.5 opacity-60" />

        <span class={[
          "absolute inset-x-0 -bottom-px h-0.5 transition",
          @active && "bg-primary",
          !@active && "bg-transparent"
        ]}>
        </span>
      </div>

      <ul
        tabindex="0"
        role="menu"
        class="dropdown-content menu menu-sm z-50 mt-2 min-w-[11rem] gap-0.5 border border-base-300 bg-base-100 p-1.5 shadow-[0_18px_40px_rgba(15,23,42,0.18)]"
      >
        <li :for={item <- @item} role="none">
          <.link
            href={item.href}
            role="menuitem"
            class={[
              "gap-2.5",
              item[:active] && "menu-active font-semibold",
              !item[:active] && "text-base-content/70"
            ]}
            aria-current={if item[:active], do: "page", else: nil}
          >
            <.icon name={item.icon} class="size-4 shrink-0" />
            {item.label}
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  attr :class, :string, default: nil

  defp public_nav_icon_link(assigns) do
    ~H"""
    <.link
      href={@href}
      aria-label={@label}
      title={@label}
      aria-current={if @active, do: "page", else: nil}
      class={[
        @class,
        "relative flex size-9 items-center justify-center transition",
        @active && "text-base-content",
        !@active && "text-base-content/65 hover:bg-base-200 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="size-4.5" />

      <span class={[
        "absolute inset-x-1.5 -bottom-px h-0.5 transition",
        @active && "bg-primary",
        !@active && "bg-transparent"
      ]}>
      </span>
    </.link>
    """
  end

  defp public_footer(assigns) do
    assigns = assign(assigns, :year, Date.utc_today().year)

    ~H"""
    <footer class="border-t border-base-300/80 bg-base-100">
      <div class="mx-auto flex min-h-10 max-w-7xl flex-wrap items-center justify-center gap-x-3 gap-y-1 px-4 py-2 text-[11px] text-base-content/55 sm:justify-between sm:px-6 lg:px-8">
        <div class="flex flex-wrap items-center justify-center gap-x-3 gap-y-1">
          <span>&copy; {@year} MeteoGargano</span>
          <span class="hidden h-3 w-px bg-base-300 sm:block" aria-hidden="true"></span>
          <span>CF 92061760713</span>
          <span class="hidden h-3 w-px bg-base-300 sm:block" aria-hidden="true"></span>
          <.link
            href="mailto:info@meteogargano.org"
            class="transition hover:text-base-content"
          >
            info@meteogargano.org
          </.link>
        </div>

        <div class="flex items-center gap-1">
          <.link
            href="mailto:info@meteogargano.org"
            class="inline-flex size-7 items-center justify-center rounded-full transition hover:bg-base-200 hover:text-base-content"
            aria-label="Email MeteoGargano"
          >
            <.icon name="hero-envelope" class="size-3.5" />
          </.link>

          <.link
            href="https://github.com/meteogargano"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex size-7 items-center justify-center rounded-full transition hover:bg-base-200 hover:text-base-content"
            aria-label="GitHub MeteoGargano"
          >
            <.github_icon class="size-3.5" />
          </.link>
        </div>
      </div>
    </footer>
    """
  end

  attr :class, :any, default: "size-4"

  defp github_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path d="M12 0.5C5.37 0.5 0 5.87 0 12.5C0 17.81 3.44 22.31 8.21 23.9C8.81 24.01 9.03 23.64 9.03 23.32C9.03 23.03 9.02 22.05 9.01 20.75C5.67 21.48 4.97 19.14 4.97 19.14C4.42 17.73 3.63 17.36 3.63 17.36C2.55 16.62 3.71 16.64 3.71 16.64C4.9 16.72 5.53 17.86 5.53 17.86C6.59 19.68 8.31 19.15 8.99 18.84C9.1 18.07 9.4 17.55 9.73 17.25C7.06 16.95 4.26 15.91 4.26 11.23C4.26 9.9 4.73 8.81 5.52 7.95C5.4 7.65 4.98 6.43 5.64 4.78C5.64 4.78 6.65 4.46 8.96 6.02C9.92 5.75 10.95 5.62 11.98 5.62C13.01 5.62 14.04 5.75 15 6.02C17.31 4.46 18.32 4.78 18.32 4.78C18.98 6.43 18.56 7.65 18.44 7.95C19.23 8.81 19.7 9.9 19.7 11.23C19.7 15.92 16.89 16.95 14.21 17.25C14.63 17.61 15 18.33 15 19.43C15 21 14.99 22.86 14.99 23.32C14.99 23.64 15.21 24.02 15.82 23.9C20.56 22.3 24 17.8 24 12.5C24 5.87 18.63 0.5 12 0.5Z" />
    </svg>
    """
  end

  defp conn_path(conn), do: conn.request_path

  defp nav_active?(nil, _section), do: false
  defp nav_active?("/", :home), do: true
  defp nav_active?(_, :home), do: false

  defp nav_active?(path, :map) do
    path == "/map" or
      path == "/compare" or
      String.starts_with?(path, "/installations/") or
      String.starts_with?(path, "/webcams")
  end

  defp nav_active?(path, :map_page), do: path == "/map"
  defp nav_active?(path, :compare), do: path == "/compare"

  defp nav_active?(path, :webcams), do: String.starts_with?(path, "/webcams")
  defp nav_active?(path, :preferences), do: path == "/preferences"

  defp nav_active?(path, :blog) do
    path == "/blog" or String.starts_with?(path, "/blog/")
  end

  defp nav_active?(path, :associazione) do
    path == "/associazione" or path == "/statuto" or String.starts_with?(path, "/associazione/")
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Back office layout with collapsible sidebar navigation.
  Used as a LiveView layout via `layout: {Voria2Web.Layouts, :manage}`.
  Receives `@inner_content` from the LiveView rendering pipeline.
  """
  def manage(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open min-h-screen bg-base-100">
      <input id="manage-drawer" type="checkbox" class="drawer-toggle" />

      <%!-- Main content column --%>
      <div class="drawer-content flex flex-col min-h-screen">
        <%!-- Mobile top bar --%>
        <div class="navbar bg-base-200/80 backdrop-blur border-b border-base-300 lg:hidden sticky top-0 z-30 px-4">
          <label
            for="manage-drawer"
            class="btn btn-ghost btn-sm mr-2"
            aria-label={gettext("Open menu")}
          >
            <.icon name="hero-bars-3" class="size-5" />
          </label>
          <a href="/manage" class="flex flex-1 items-center gap-2 min-w-0">
            <div class="size-8 shrink-0">
              <img
                src={~p"/images/app-logo.svg"}
                alt="MeteoGargano logo"
                class="block size-full object-contain"
              />
            </div>
            <span class="truncate font-bold text-primary text-sm">MeteoGargano</span>
          </a>
        </div>

        <%!-- Page content --%>
        <main class="flex-1 p-5 lg:p-8 !pt-3">
          {@inner_content}
        </main>
      </div>

      <%!-- Sidebar --%>
      <div class="drawer-side z-40">
        <label for="manage-drawer" aria-label={gettext("Close menu")} class="drawer-overlay"></label>
        <aside class="flex flex-col w-72 min-h-full bg-base-200 border-r border-base-300">
          <%!-- Logo --%>
          <a
            href="/manage"
            class="flex items-center gap-3 px-5 py-5 border-b border-base-300 hover:bg-base-300/50 transition-colors"
          >
            <.brand_block
              logo_class="size-10"
              title_class="text-sm tracking-[0.18em] text-base-content"
              subtitle_class="text-xs text-base-content/40"
            >
              {gettext("Network Management")}
            </.brand_block>
          </a>

          <%!-- Navigation --%>
          <nav class="flex-1 px-3 py-4 space-y-5 overflow-y-auto">
            <div>
              <p class="text-[10px] font-semibold uppercase tracking-widest text-base-content/35 px-3 mb-1">
                {gettext("Network")}
              </p>
              <ul class="menu menu-sm p-0 gap-0.5">
                <li>
                  <.link
                    navigate={~p"/manage/installations"}
                    class={[
                      "gap-3 rounded-lg",
                      active_class(assigns[:active_section], :installations)
                    ]}
                  >
                    <.icon name="hero-map-pin" class="size-4 shrink-0" /> {gettext("Installations")}
                  </.link>
                </li>
              </ul>
            </div>

            <div>
              <p class="text-[10px] font-semibold uppercase tracking-widest text-base-content/35 px-3 mb-1">
                {gettext("Measurements")}
              </p>
              <ul class="menu menu-sm p-0 gap-0.5">
                <li>
                  <.link
                    navigate={~p"/manage/measurement_types"}
                    class={[
                      "gap-3 rounded-lg",
                      active_class(assigns[:active_section], :measurement_types)
                    ]}
                  >
                    <.icon name="hero-beaker" class="size-4 shrink-0" /> {gettext("Measurement Types")}
                  </.link>
                </li>
              </ul>
            </div>

            <div :if={assigns[:current_user] && Map.get(assigns[:current_user], :admin)}>
              <p class="text-[10px] font-semibold uppercase tracking-widest text-base-content/35 px-3 mb-1">
                {gettext("Admin")}
              </p>
              <ul class="menu menu-sm p-0 gap-0.5">
                <li>
                  <.link
                    navigate={~p"/manage/faults"}
                    class={[
                      "gap-3 rounded-lg",
                      active_class(assigns[:active_section], :faults)
                    ]}
                  >
                    <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" /> {gettext(
                      "Faults"
                    )}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/manage/measurements/editor"}
                    class={[
                      "gap-3 rounded-lg",
                      active_class(assigns[:active_section], :measurements)
                    ]}
                  >
                    <.icon name="hero-pencil-square" class="size-4 shrink-0" /> {gettext(
                      "Measurements Editor"
                    )}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/manage/webcam-shots/purge"}
                    class={[
                      "gap-3 rounded-lg",
                      active_class(assigns[:active_section], :webcam_shots)
                    ]}
                  >
                    <.icon name="hero-trash" class="size-4 shrink-0" /> {gettext("Webcam Shot Purge")}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/manage/blog_pages"}
                    class={[
                      "gap-3 rounded-lg",
                      active_class(assigns[:active_section], :blog_pages)
                    ]}
                  >
                    <.icon name="hero-newspaper" class="size-4 shrink-0" /> {gettext("Blog Pages")}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/manage/blogcontent"}
                    class={[
                      "gap-3 rounded-lg",
                      active_class(assigns[:active_section], :blogcontent)
                    ]}
                  >
                    <.icon name="hero-document-text" class="size-4 shrink-0" /> {gettext(
                      "Blog Content"
                    )}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/manage/users"}
                    class={[
                      "gap-3 rounded-lg",
                      active_class(assigns[:active_section], :users)
                    ]}
                  >
                    <.icon name="hero-users" class="size-4 shrink-0" /> {gettext("Users")}
                  </.link>
                </li>
              </ul>
            </div>
          </nav>

          <%!-- User footer --%>
          <div class="border-t border-base-300 px-3 py-3 space-y-1">
            <%!-- User card --%>
            <div
              :if={assigns[:current_user]}
              class="flex items-center gap-3 px-3 py-2.5 rounded-lg"
            >
              <div class="size-8 rounded-full bg-primary text-primary-content font-bold text-xs flex items-center justify-center shrink-0 select-none">
                {String.upcase(String.first(assigns[:current_user].name || "?"))}
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-xs font-semibold truncate leading-tight">
                  {assigns[:current_user].name}
                </p>
                <p class="text-[10px] text-base-content/40 truncate leading-tight">
                  {assigns[:current_user].email}
                </p>
              </div>
            </div>

            <ul class="menu menu-sm p-0 gap-0.5">
              <li>
                <.link
                  navigate={~p"/manage/profile"}
                  class={[
                    "gap-3 rounded-lg",
                    active_class(assigns[:active_section], :profile)
                  ]}
                >
                  <.icon name="hero-user-circle" class="size-4 shrink-0" /> {gettext(
                    "Profile & Password"
                  )}
                </.link>
              </li>
              <li>
                <.link
                  href={~p"/sign-out"}
                  method="delete"
                  class="gap-3 rounded-lg text-error hover:text-error hover:bg-error/10"
                >
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4 shrink-0" /> {gettext(
                    "Sign Out"
                  )}
                </.link>
              </li>
            </ul>
          </div>
        </aside>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp active_class(active_section, section) do
    if active_section == section, do: "active", else: ""
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  attr :class, :string, default: nil

  def theme_toggle(assigns) do
    ~H"""
    <div class={[
      "card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full",
      @class
    ]}>
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
