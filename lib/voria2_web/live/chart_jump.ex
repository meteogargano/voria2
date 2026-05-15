defmodule Voria2Web.ChartJump do
  use Gettext, backend: Voria2Web.Gettext

  def build_form(attrs \\ %{}) do
    Phoenix.Component.to_form(
      %{
        "input" => Map.get(attrs, "input", ""),
        "utc_iso" => Map.get(attrs, "utc_iso", "")
      },
      as: :jump
    )
  end

  def sync_form_from_datetime(%DateTime{} = datetime) do
    build_form(%{
      "input" => Calendar.strftime(datetime, "%d/%m/%Y %H:%M"),
      "utc_iso" => DateTime.to_iso8601(datetime)
    })
  end

  def resolve_target_datetime(params, now \\ DateTime.utc_now()) do
    input = Map.get(params, "input", "")
    utc_iso = Map.get(params, "utc_iso", "")

    case parse_utc_iso(utc_iso) do
      {:ok, datetime} ->
        target = min_datetime(datetime, now)
        {:ok, %{target: target, form: sync_form_from_datetime(target)}}

      {:error, :invalid_datetime} ->
        {:error,
         %{
           form: build_form(%{"input" => input}),
           error: gettext("Enter a date and time as dd/mm/yyyy hh:mm.")
         }}
    end
  end

  defp parse_utc_iso(utc_iso) when is_binary(utc_iso) and utc_iso != "" do
    case DateTime.from_iso8601(utc_iso) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :invalid_datetime}
    end
  end

  defp parse_utc_iso(_), do: {:error, :invalid_datetime}

  defp min_datetime(a, b) do
    if DateTime.compare(a, b) == :gt, do: b, else: a
  end
end
