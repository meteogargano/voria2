defmodule Voria2.Storage.R2 do
  @behaviour Voria2.Storage

  @impl true
  def list(prefix, bucket) do
    case ExAws.S3.list_objects_v2(bucket, prefix: prefix) |> ExAws.request() do
      {:ok, %{body: %{contents: contents}}} ->
        {:ok,
         Enum.map(contents, fn item ->
           %{
             key: item.key,
             size: parse_integer(item.size),
             last_modified: blank_to_nil(item.last_modified),
             etag: blank_to_nil(item.e_tag),
             content_type: nil
           }
         end)}

      {:ok, %{body: _body}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def upload(binary, key, bucket) do
    IO.inspect("=== UPLOAD DEBUG ===")
    IO.inspect("Bucket: #{bucket}")
    IO.inspect("Key: #{key}")
    IO.inspect("Binary size: #{byte_size(binary)}")

    config = ExAws.Config.new(:s3)
    IO.inspect("ExAws Config: #{inspect(config)}")

    operation = ExAws.S3.put_object(bucket, key, binary)
    IO.inspect("Operation: #{inspect(operation)}")

    result = operation |> ExAws.request()
    IO.inspect("Result: #{inspect(result)}")

    case result do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key, bucket) do
    case ExAws.S3.delete_object(bucket, key) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def download(key, bucket) do
    case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
      {:ok, %{body: body, headers: headers}} when is_binary(body) ->
        {:ok,
         %{
           body: body,
           content_type: header_value(headers, "content-type"),
           size: parse_integer(header_value(headers, "content-length"))
         }}

      {:ok, %{body: body}} when is_binary(body) ->
        {:ok, %{body: body, content_type: nil, size: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp header_value(headers, name) do
    headers
    |> Enum.find_value(fn {header_name, value} ->
      if String.downcase(header_name) == name, do: value
    end)
    |> blank_to_nil()
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
