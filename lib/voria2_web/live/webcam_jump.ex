defmodule Voria2Web.WebcamJump do
  require Ash.Query
  use Gettext, backend: Voria2Web.Gettext

  def build_form(attrs \\ %{}) do
    Phoenix.Component.to_form(
      %{
        "input" => Map.get(attrs, "input", ""),
        "utc_iso" => Map.get(attrs, "utc_iso", ""),
        "webcam_id" => Map.get(attrs, "webcam_id", "")
      },
      as: :jump
    )
  end

  def jump_to_datetime(webcam_id, params) do
    input = Map.get(params, "input", "")
    utc_iso = Map.get(params, "utc_iso", "")

    with {:ok, target} <- parse_utc_iso(utc_iso),
         %{} = shot <- find_closest_shot(webcam_id, target) do
      {shots, viewing_date} = load_shots_for_date(webcam_id, DateTime.to_date(shot.captured_at))
      current_index = Enum.find_index(shots, &(&1.id == shot.id)) || 0

      {:ok,
       %{
         form: build_form(%{"input" => input, "utc_iso" => utc_iso}),
         shots: shots,
         current_shot: shot,
         current_index: current_index,
         viewing_date: viewing_date
       }}
    else
      {:error, :invalid_datetime} ->
        {:error,
         %{
           form: build_form(%{"input" => input}),
           error: gettext("Enter a date and time as dd/mm/yyyy hh:mm.")
         }}

      nil ->
        {:error,
         %{
           form: build_form(%{"input" => input}),
           error: gettext("No shots found for this webcam.")
         }}
    end
  end

  def load_shots_for_date(webcam_id, date) do
    from = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    to = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    shots =
      case Voria2.Network.webcam_shot_history(webcam_id, from, to, authorize?: false) do
        {:ok, list} -> list
        _ -> []
      end

    {shots, date}
  end

  defp parse_utc_iso(utc_iso) when is_binary(utc_iso) and utc_iso != "" do
    case DateTime.from_iso8601(utc_iso) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :invalid_datetime}
    end
  end

  defp parse_utc_iso(_), do: {:error, :invalid_datetime}

  defp find_closest_shot(webcam_id, target) do
    before_shot = latest_shot_before(webcam_id, target)
    after_shot = earliest_shot_after(webcam_id, target)

    choose_closest_shot(before_shot, after_shot, target)
  end

  defp latest_shot_before(webcam_id, target) do
    Voria2.Network.WebcamShot
    |> Ash.Query.filter(webcam_id == ^webcam_id and captured_at <= ^target)
    |> Ash.Query.sort(captured_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> List.first()
  end

  defp earliest_shot_after(webcam_id, target) do
    Voria2.Network.WebcamShot
    |> Ash.Query.filter(webcam_id == ^webcam_id and captured_at >= ^target)
    |> Ash.Query.sort(captured_at: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> List.first()
  end

  defp choose_closest_shot(nil, nil, _target), do: nil
  defp choose_closest_shot(shot, nil, _target), do: shot
  defp choose_closest_shot(nil, shot, _target), do: shot

  defp choose_closest_shot(before_shot, after_shot, target) do
    before_diff = abs(DateTime.diff(before_shot.captured_at, target, :microsecond))
    after_diff = abs(DateTime.diff(after_shot.captured_at, target, :microsecond))

    if before_diff <= after_diff, do: before_shot, else: after_shot
  end
end
