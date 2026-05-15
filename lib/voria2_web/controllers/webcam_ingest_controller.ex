defmodule Voria2Web.WebcamIngestController do
  use Voria2Web, :controller

  @default_max_bytes 5 * 1024 * 1024

  def verify(conn, _params) do
    webcam = conn.assigns.ingest_webcam
    json(conn, %{ok: true, webcam_id: webcam.id, webcam_name: webcam.name})
  end

  def create(conn, %{"image" => %Plug.Upload{} = upload}) do
    webcam = conn.assigns.ingest_webcam
    max_bytes = Application.get_env(:voria2, :max_webcam_upload_bytes, @default_max_bytes)

    with {:ok, size} <- check_size(upload.path, max_bytes),
         _ = size,
         binary = File.read!(upload.path),
         result <- Voria2.WebcamIngest.process(webcam, binary) do
      case result do
        {:ok, shot} ->
          conn |> put_status(201) |> json(%{ok: true, shot_id: shot.id, s3_key: shot.s3_key})

        {:duplicate, shot} ->
          conn |> json(%{ok: true, duplicate: true, shot_id: shot.id, s3_key: shot.s3_key})

        {:error, reason} ->
          conn |> put_status(422) |> json(%{ok: false, error: format_error(reason)})
      end
    else
      {:error, :too_large} ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: "image exceeds maximum allowed size"})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{ok: false, error: format_error(reason)})
    end
  end

  def create(conn, _params) do
    conn |> put_status(422) |> json(%{ok: false, error: "missing image upload"})
  end

  defp check_size(path, max_bytes) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= max_bytes -> {:ok, size}
      {:ok, _} -> {:error, :too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_error({:invalid_image, reason}), do: "invalid image: #{inspect(reason)}"
  defp format_error(other), do: inspect(other)
end
