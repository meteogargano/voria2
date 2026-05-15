defmodule Voria2Web.ManageComponents do
  @moduledoc """
  Reusable UI components for the Voria2 back office management interface.
  """
  use Phoenix.Component
  use Gettext, backend: Voria2Web.Gettext

  import Phoenix.HTML
  import Voria2Web.CoreComponents
  alias Phoenix.LiveView.JS

  # ---------------------------------------------------------------------------
  # Breadcrumb
  # ---------------------------------------------------------------------------

  @doc """
  Renders a breadcrumb navigation trail.

  ## Examples

      <.breadcrumb crumbs={[{"Installations", ~p"/manage/installations"}, {"My Station", nil}]} />
  """
  attr :crumbs, :list, required: true, doc: "list of {label, path | nil} tuples"

  def breadcrumb(assigns) do
    ~H"""
    <div class="breadcrumbs text-sm mb-2 text-base-content/60">
      <ul>
        <li>
          <.link navigate="/manage" class="hover:text-base-content">
            <.icon name="hero-home-micro" class="size-3.5" />
          </.link>
        </li>
        <li :for={{label, path} <- @crumbs}>
          <.link :if={path} navigate={path} class="hover:text-base-content">
            {label}
          </.link>
          <span :if={!path} class="text-base-content font-medium">{label}</span>
        </li>
      </ul>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Empty State
  # ---------------------------------------------------------------------------

  @doc """
  Renders a friendly empty state with icon, title, description, and optional actions.
  """
  attr :title, :string, required: true
  attr :message, :string, default: nil
  attr :icon, :string, default: "hero-inbox"
  slot :actions

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-20 text-center">
      <div class="size-16 rounded-2xl bg-base-200 flex items-center justify-center mb-5 ring-1 ring-base-300">
        <.icon name={@icon} class="size-8 text-base-content/30" />
      </div>
      <h3 class="text-base font-semibold text-base-content">{@title}</h3>
      <p :if={@message} class="text-sm text-base-content/50 mt-1.5 max-w-xs leading-relaxed">
        {@message}
      </p>
      <div :if={@actions != []} class="mt-4 flex flex-wrap gap-3 justify-center">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Resource Table
  # ---------------------------------------------------------------------------

  @doc """
  Wraps the core table with empty state support and consistent manage-section styling.
  Rows must be a plain list (not a LiveStream).
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :empty_title, :string, default: nil
  attr :empty_message, :string, default: nil
  attr :empty_icon, :string, default: "hero-inbox"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "row action buttons"
  slot :empty_actions, doc: "buttons shown in empty state"

  def resource_table(assigns) do
    ~H"""
    <div>
      <div :if={@rows == []}>
        <.empty_state
          title={@empty_title || gettext("Nothing here yet")}
          message={@empty_message}
          icon={@empty_icon}
        >
          <:actions>{render_slot(@empty_actions)}</:actions>
        </.empty_state>
      </div>
      <div :if={@rows != []} class="overflow-x-auto  border border-base-300">
        <table class="table table-zebra w-full">
          <thead>
            <tr class="bg-base-200/60">
              <th
                :for={col <- @col}
                class="text-xs font-semibold uppercase tracking-wide text-base-content/50"
              >
                {col[:label]}
              </th>
              <th
                :if={@action != []}
                class="w-px text-xs font-semibold uppercase tracking-wide text-base-content/50"
              >
                <span class="sr-only">{gettext("Actions")}</span>
              </th>
            </tr>
          </thead>
          <tbody id={@id}>
            <tr :for={row <- @rows} class="hover">
              <td :for={col <- @col}>
                {render_slot(col, row)}
              </td>
              <td :if={@action != []} class="w-px">
                <div class="flex items-center gap-1">
                  <%= for action <- @action do %>
                    {render_slot(action, row)}
                  <% end %>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Detail Section
  # ---------------------------------------------------------------------------

  @doc """
  Renders a card-style key-value detail section.

  ## Examples

      <.detail_section title="Location">
        <:item label="City">{@installation.city}</:item>
        <:item label="Country">{@installation.country}</:item>
      </.detail_section>
  """
  attr :title, :string, default: nil
  attr :class, :string, default: nil

  slot :item, required: true do
    attr :label, :string, required: true
  end

  slot :actions

  def detail_section(assigns) do
    ~H"""
    <div class={[" border border-base-300 bg-base-100 overflow-hidden mt-0", @class]}>
      <dl class="divide-y divide-base-300">
        <div :for={item <- @item} class="px-6 py-3.5 flex items-baseline gap-4 sm:gap-8">
          <dt class="text-xs font-medium text-base-content/50 uppercase tracking-wide w-32 shrink-0">
            {item.label}
          </dt>
          <dd class="text-sm text-base-content flex-1 min-w-0">
            {render_slot(item)}
          </dd>
        </div>
      </dl>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Status Badge
  # ---------------------------------------------------------------------------

  @doc """
  Renders an active/inactive badge.
  """
  attr :active, :boolean, required: true
  attr :active_label, :string, default: nil
  attr :inactive_label, :string, default: nil

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm font-medium",
      @active && "badge-success",
      !@active && "badge-warning badge-outline"
    ]}>
      {if @active,
        do: @active_label || gettext("Active"),
        else: @inactive_label || gettext("Inactive")}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Tab Bar
  # ---------------------------------------------------------------------------

  @doc """
  Renders a tab navigation bar. Uses LiveView patch for navigation.

  Each tab is `{id_atom, label_string, patch_path_string}`.
  """
  attr :tabs, :list, required: true, doc: "list of {id, label, patch_path} tuples"
  attr :active_tab, :atom, required: true

  def tab_bar(assigns) do
    ~H"""
    <div class="flex gap-1 border-b border-base-content/10 mt-2 mb-0" role="tablist">
      <a
        :for={{id, label, path} <- @tabs}
        role="tab"
        class={[
          "px-4 py-2 text-sm cursor-pointer transition-colors",
          @active_tab == id &&
            "bg-base-content/10 text-base-content font-medium",
          @active_tab != id &&
            "text-base-content/40 hover:text-base-content/70"
        ]}
        phx-click={JS.patch(path)}
      >
        {label}
      </a>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Confirm Modal
  # ---------------------------------------------------------------------------

  @doc """
  Renders a confirmation dialog using the HTML dialog element.

  Toggle with JS.exec("id", "showModal") / JS.exec("id", "close").
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :message, :string, default: nil
  attr :confirm_label, :string, default: nil
  attr :cancel_label, :string, default: nil
  attr :confirm_event, :string, required: true
  attr :confirm_value, :map, default: %{}
  attr :danger, :boolean, default: false

  def confirm_modal(assigns) do
    ~H"""
    <dialog id={@id} class="modal modal-bottom sm:modal-middle">
      <div class="modal-box">
        <h3 class="font-semibold text-lg">{@title}</h3>
        <p :if={@message} class="py-4 text-base-content/70 text-sm">{@message}</p>
        <div class="modal-action gap-2">
          <form method="dialog">
            <button class="btn btn-ghost btn-sm">{@cancel_label || gettext("Cancel")}</button>
          </form>
          <button
            class={["btn btn-sm", @danger && "btn-error", !@danger && "btn-primary"]}
            phx-click={@confirm_event}
            phx-value-id={@confirm_value[:id]}
            onclick={"document.getElementById('#{@id}').close()"}
          >
            {@confirm_label || gettext("Confirm")}
          </button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end

  # ---------------------------------------------------------------------------
  # API Key Card
  # ---------------------------------------------------------------------------

  @doc """
  Renders an API key row with masked key, label, date, and revoke action.
  """
  attr :api_key, :any, required: true, doc: "StationApiKey or WebcamApiKey record"
  attr :revoke_event, :string, default: "revoke_key"
  attr :modal_id, :string, required: true

  def api_key_card(assigns) do
    ~H"""
    <div class="flex items-center gap-4 px-4 py-3 rounded-lg border border-base-300 bg-base-100">
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <code class="text-xs font-mono bg-base-200 px-2 py-0.5 rounded text-base-content/80">
            {mask_key(@api_key.key)}
          </code>
          <span :if={@api_key.label} class="text-xs text-base-content/50">
            {@api_key.label}
          </span>
        </div>
        <p class="text-xs text-base-content/40 mt-0.5">
          Created {gettext("Created %{date}", date: format_date(@api_key.inserted_at))}
        </p>
      </div>
      <button
        class="btn btn-ghost btn-xs text-error hover:bg-error/10"
        onclick={"document.getElementById('#{@modal_id}-#{@api_key.id}').showModal()"}
      >
        <.icon name="hero-trash" class="size-3.5" /> {gettext("Revoke")}
      </button>

      <.confirm_modal
        id={"#{@modal_id}-#{@api_key.id}"}
        title={gettext("Revoke API Key")}
        message={
          gettext(
            "This key will stop working immediately. Any devices using it will be unable to connect."
          )
        }
        confirm_label={gettext("Revoke")}
        confirm_event={@revoke_event}
        confirm_value={%{id: @api_key.id}}
        danger={true}
      />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Key Reveal Modal
  # ---------------------------------------------------------------------------

  @doc """
  One-time API key display modal. Shows after generation. Content cleared on close.
  """
  attr :id, :string, default: "key-reveal-modal"
  attr :key, :string, default: nil

  def key_reveal_modal(assigns) do
    ~H"""
    <div class="modal modal-open" role="dialog" id={@id}>
      <div class="modal-box max-w-lg">
        <div class="flex items-center gap-3 mb-5">
          <div class="bg-success/15  p-2.5">
            <.icon name="hero-key" class="size-6 text-success" />
          </div>
          <div>
            <h3 class="font-semibold text-lg leading-tight">{gettext("API Key Generated")}</h3>
            <p class="text-xs text-base-content/50 mt-0.5">{gettext("Your new key is ready")}</p>
          </div>
        </div>

        <div class="alert alert-warning mb-5">
          <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
          <span class="text-sm font-medium">
            {raw(gettext("Save this key now — it will <strong>never</strong> be shown again."))}
          </span>
        </div>

        <div class="bg-base-200  p-4">
          <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-2">
            {gettext("API Key")}
          </p>
          <code
            id={"#{@id}-value"}
            class="block font-mono text-sm break-all leading-relaxed select-all"
          >
            {@key}
          </code>
        </div>

        <button
          class="btn btn-outline btn-sm w-full mt-3 gap-2"
          data-key-target={"#{@id}-value"}
          data-copy-text={gettext("Copy to clipboard")}
          data-copied-text={gettext("Copied!")}
          onclick="var el=document.getElementById(this.dataset.keyTarget);var text=el.textContent.trim();var done=()=>{this.innerHTML='<span>'+this.dataset.copiedText+'</span>';setTimeout(()=>{this.innerHTML='<span>'+this.dataset.copyText+'</span>'},2000)};if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(text).then(done)}else{var textarea=document.createElement('textarea');textarea.value=text;textarea.setAttribute('readonly','');textarea.style.position='absolute';textarea.style.left='-9999px';document.body.appendChild(textarea);textarea.select();document.execCommand('copy');document.body.removeChild(textarea);done()}"
        >
          <span>{gettext("Copy to clipboard")}</span>
        </button>

        <div class="modal-action mt-4 pt-4 border-t border-base-300">
          <button class="btn btn-primary w-full" phx-click="close_key_modal">
            {gettext("I've saved the key — close")}
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_key_modal"></div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Fault List
  # ---------------------------------------------------------------------------

  @doc """
  Renders a fault list with resolve button for admins.
  """
  attr :faults, :list, required: true
  attr :can_resolve, :boolean, default: false
  attr :empty_message, :string, default: nil

  def fault_list(assigns) do
    ~H"""
    <div>
      <div :if={@faults == []} class="text-sm text-base-content/50 py-8 text-center">
        <.icon name="hero-check-circle" class="size-8 mx-auto mb-2 text-success/60" />
        {@empty_message || gettext("No faults recorded.")}
      </div>
      <div :if={@faults != []} class="space-y-2">
        <div
          :for={fault <- @faults}
          class={[
            "flex items-start gap-4 px-4 py-3 rounded-lg border text-sm",
            is_nil(fault.resolved_at) && "border-error/30 bg-error/5",
            !is_nil(fault.resolved_at) && "border-base-300 bg-base-100"
          ]}
        >
          <.icon
            name={
              if is_nil(fault.resolved_at), do: "hero-exclamation-circle", else: "hero-check-circle"
            }
            class={[
              "size-4 shrink-0 mt-0.5",
              is_nil(fault.resolved_at) && "text-error",
              !is_nil(fault.resolved_at) && "text-success"
            ]}
          />
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 flex-wrap">
              <span class="font-medium capitalize">
                {fault.fault_type |> to_string() |> String.replace("_", " ")}
              </span>
              <span class={[
                "badge badge-xs",
                is_nil(fault.resolved_at) && "badge-error",
                !is_nil(fault.resolved_at) && "badge-success"
              ]}>
                {if is_nil(fault.resolved_at), do: gettext("Active"), else: gettext("Resolved")}
              </span>
            </div>
            <p class="text-base-content/60 mt-0.5">{fault.reason}</p>
            <p class="text-xs text-base-content/40 mt-1">
              {gettext("Detected %{datetime}", datetime: format_datetime(fault.detected_at))}
              <span :if={!is_nil(fault.resolved_at)}>
                · {gettext("Resolved %{datetime}", datetime: format_datetime(fault.resolved_at))}
              </span>
            </p>
          </div>
          <button
            :if={@can_resolve && is_nil(fault.resolved_at)}
            class="btn btn-xs btn-ghost text-success hover:bg-success/10 shrink-0"
            onclick={"document.getElementById('resolve-fault-#{fault.id}').showModal()"}
          >
            {gettext("Resolve")}
          </button>
          <.confirm_modal
            :if={@can_resolve && is_nil(fault.resolved_at)}
            id={"resolve-fault-#{fault.id}"}
            title={gettext("Resolve Fault")}
            message={gettext("Mark this fault as resolved?")}
            confirm_label={gettext("Resolve")}
            confirm_event="resolve_fault"
            confirm_value={%{id: fault.id}}
          />
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp mask_key(key) when is_binary(key) do
    case String.split(key, "_", parts: 2) do
      [prefix, rest] ->
        masked = String.duplicate("•", max(0, String.length(rest) - 4))
        last4 = String.slice(rest, -4, 4)
        "#{prefix}_#{masked}#{last4}"

      _ ->
        String.slice(key, 0, 8) <> "••••••••"
    end
  end

  defp mask_key(_), do: "••••••••••••"

  defp format_date(nil), do: "—"

  defp format_date(%DateTime{} = dt),
    do: Calendar.strftime(DateTime.to_date(dt), "%b %d, %Y")

  defp format_date(%NaiveDateTime{} = ndt),
    do: Calendar.strftime(NaiveDateTime.to_date(ndt), "%b %d, %Y")

  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %d, %Y")

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%b %d, %Y %H:%M")

  defp format_datetime(%NaiveDateTime{} = ndt),
    do: Calendar.strftime(ndt, "%b %d, %Y %H:%M")
end
