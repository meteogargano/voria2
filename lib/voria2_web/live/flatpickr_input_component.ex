defmodule Voria2Web.FlatpickrInputComponent do
  use Phoenix.Component

  attr :id, :string, required: true
  attr :field_name, :string, required: true
  attr :display_name, :string, default: nil
  attr :label, :string, default: nil
  attr :value, :any, default: nil
  attr :display_value, :any, default: nil
  attr :hidden_id, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :submit_mode, :atom, values: [:date_iso, :datetime_local, :utc_iso], default: :date_iso
  attr :minute_increment, :integer, default: 5
  attr :force_custom_mobile, :boolean, default: true
  attr :push_event, :string, default: nil
  attr :class, :string, default: nil
  attr :input_class, :any, default: nil

  attr :rest, :global,
    include:
      ~w(autocomplete disabled form readonly required phx-debounce phx-blur phx-focus phx-change)

  def date_picker(assigns) do
    assigns = assign(assigns, :picker, :date)

    ~H"""
    <.render_picker
      id={@id}
      picker={@picker}
      submit_mode={@submit_mode}
      field_name={@field_name}
      display_name={@display_name}
      label={@label}
      value={@value}
      display_value={@display_value}
      hidden_id={@hidden_id}
      placeholder={@placeholder}
      minute_increment={@minute_increment}
      force_custom_mobile={@force_custom_mobile}
      push_event={@push_event}
      class={@class}
      input_class={@input_class}
      {@rest}
    />
    """
  end

  attr :id, :string, required: true
  attr :field_name, :string, required: true
  attr :display_name, :string, default: nil
  attr :label, :string, default: nil
  attr :value, :any, default: nil
  attr :display_value, :any, default: nil
  attr :hidden_id, :string, default: nil
  attr :placeholder, :string, default: nil

  attr :submit_mode, :atom,
    values: [:date_iso, :datetime_local, :utc_iso],
    default: :datetime_local

  attr :minute_increment, :integer, default: 5
  attr :force_custom_mobile, :boolean, default: true
  attr :push_event, :string, default: nil
  attr :class, :string, default: nil
  attr :input_class, :any, default: nil

  attr :rest, :global,
    include:
      ~w(autocomplete disabled form readonly required phx-debounce phx-blur phx-focus phx-change)

  def datetime_picker(assigns) do
    assigns = assign(assigns, :picker, :datetime)

    ~H"""
    <.render_picker
      id={@id}
      picker={@picker}
      submit_mode={@submit_mode}
      field_name={@field_name}
      display_name={@display_name}
      label={@label}
      value={@value}
      display_value={@display_value}
      hidden_id={@hidden_id}
      placeholder={@placeholder}
      minute_increment={@minute_increment}
      force_custom_mobile={@force_custom_mobile}
      push_event={@push_event}
      class={@class}
      input_class={@input_class}
      {@rest}
    />
    """
  end

  attr :id, :string, required: true
  attr :picker, :atom, values: [:date, :datetime], required: true
  attr :submit_mode, :atom, values: [:date_iso, :datetime_local, :utc_iso], required: true
  attr :field_name, :string, required: true
  attr :display_name, :string, default: nil
  attr :label, :string, default: nil
  attr :value, :any, default: nil
  attr :display_value, :any, default: nil
  attr :hidden_id, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :minute_increment, :integer, default: 5
  attr :force_custom_mobile, :boolean, default: true
  attr :push_event, :string, default: nil
  attr :class, :string, default: nil
  attr :input_class, :any, default: nil

  attr :rest, :global,
    include:
      ~w(autocomplete disabled form readonly required phx-debounce phx-blur phx-focus phx-change)

  def render_picker(assigns) do
    assigns =
      assigns
      |> assign(:root_id, "#{assigns.id}-root")
      |> assign(:hidden_id, assigns.hidden_id || "#{assigns.id}-value")
      |> assign(:value, normalize_value(assigns.value))
      |> assign(:display_value, normalize_value(assigns.display_value))
      |> assign_new(:input_class, fn -> "input input-sm input-bordered w-full min-w-0" end)

    ~H"""
    <div
      id={@root_id}
      phx-hook="FlatpickrInput"
      data-picker={@picker}
      data-submit-mode={@submit_mode}
      data-minute-increment={@minute_increment}
      data-force-custom-mobile={@force_custom_mobile}
      data-push-event={@push_event}
      data-position="auto left"
      class={@class}
    >
      <label :if={@label} for={@id} class="label mb-1">{@label}</label>
      <input
        id={@id}
        type="text"
        name={@display_name}
        value={@display_value}
        data-role="flatpickr-visible-input"
        data-server-value={@display_value}
        placeholder={@placeholder}
        class={[@input_class, "flatpickr-control"]}
        autocomplete={@rest[:autocomplete] || "off"}
        disabled={@rest[:disabled]}
        form={@rest[:form]}
        readonly={@rest[:readonly]}
        required={@rest[:required]}
        phx-debounce={@rest["phx-debounce"]}
        phx-blur={@rest["phx-blur"]}
        phx-focus={@rest["phx-focus"]}
        phx-change={@rest["phx-change"]}
      />
      <input
        id={@hidden_id}
        type="hidden"
        name={@field_name}
        value={@value}
        data-role="flatpickr-hidden-input"
        data-server-value={@value}
        disabled={@rest[:disabled]}
        form={@rest[:form]}
      />
    </div>
    """
  end

  defp normalize_value(nil), do: ""
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(%Date{} = value), do: Date.to_iso8601(value)

  defp normalize_value(%NaiveDateTime{} = value) do
    Calendar.strftime(value, "%Y-%m-%dT%H:%M")
  end

  defp normalize_value(%DateTime{} = value) do
    value
    |> DateTime.to_naive()
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  defp normalize_value(value), do: to_string(value)
end
