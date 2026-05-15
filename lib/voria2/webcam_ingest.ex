defmodule Voria2.WebcamIngest do
  require Ash.Query

  def process(webcam, binary) do
    hash = Base.encode16(:crypto.hash(:sha256, binary), case: :lower)

    with :new <- check_duplicate(hash),
         {:ok, img} <- Image.from_binary(binary),
         {width, height, _bands} = Image.shape(img),
         {:ok, webp_binary} <- Image.write(img, :memory, suffix: ".webp"),
         key =
           "webcams/#{webcam.id}/#{Date.utc_today()}/#{System.unique_integer([:positive])}.webp",
         bucket = Application.get_env(:voria2, :storage_bucket, "voria2-media"),
         {:ok, _} <- Voria2.Storage.upload(webp_binary, key, bucket),
         {:ok, shot} <-
           Voria2.Network.record_webcam_shot(
             %{
               webcam_id: webcam.id,
               captured_at: DateTime.utc_now(),
               s3_key: key,
               s3_bucket: bucket,
               original_hash: hash,
               width: width,
               height: height,
               file_size_bytes: byte_size(webp_binary)
             },
             authorize?: false
           ) do
      Voria2.Cache.broadcast_webcam_shot(webcam.id)
      Voria2.Cache.touch_webcam(webcam.id)
      Voria2.Network.FaultClearer.clear_webcam(webcam.id)
      {:ok, shot}
    else
      {:duplicate, shot} -> {:duplicate, shot}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_duplicate(hash) do
    case Voria2.Network.get_webcam_shot_by_hash(hash,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, nil} -> :new
      {:ok, shot} -> {:duplicate, shot}
      _ -> :new
    end
  end
end
