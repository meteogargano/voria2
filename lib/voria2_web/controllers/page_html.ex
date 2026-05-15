defmodule Voria2Web.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use Voria2Web, :html

  embed_templates "page_html/*"

  def article_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%B %-d, %Y")

  def article_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  def latest_shot_url(%{s3_key: s3_key}) when is_binary(s3_key),
    do: Voria2.Storage.public_url(s3_key)

  def latest_shot_url(_shot), do: nil

  def latest_shot_viewer_path(%{webcam: %{id: webcam_id}}), do: ~p"/webcams/#{webcam_id}/viewer"
  def latest_shot_viewer_path(_shot), do: nil

  def latest_shot_timestamp(%{captured_at: %DateTime{} = captured_at}) do
    Calendar.strftime(captured_at, "%d %b %Y, %H:%M")
  end

  def latest_shot_timestamp(_shot), do: nil

  def excerpt(body) when is_binary(body) do
    body
    |> String.replace(~r/<!--.*?-->/us, " ")
    |> String.replace(~r/<(?:script|style)\b[^>]*>.*?<\/(?:script|style)>/uis, " ")
    |> String.replace(~r/<![^>]*>/u, " ")
    |> String.replace(~r/<\/?[a-zA-Z][^>]*>/u, " ")
    |> String.replace(~r/&[a-zA-Z0-9#]+;/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> truncate(180)
  end

  def excerpt(_body), do: ""

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) <= max_length do
      text
    else
      String.slice(text, 0, max_length - 1) <> "…"
    end
  end
end
