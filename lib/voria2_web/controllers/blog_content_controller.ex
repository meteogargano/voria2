defmodule Voria2Web.BlogContentController do
  use Voria2Web, :controller

  def show(conn, %{"path" => segments} = params) do
    current_user = conn.assigns[:current_user]

    if current_user && current_user.admin do
      with [filename] <- segments,
           key <- Voria2.BlogContent.object_key(filename),
           {:ok, file} <- Voria2.BlogContent.download(key) do
        disposition = content_disposition(params)

        conn
        |> put_resp_content_type(
          file.content_type || MIME.from_path(filename) || "application/octet-stream"
        )
        |> put_resp_header("content-disposition", disposition)
        |> send_resp(200, file.body)
      else
        _ ->
          send_resp(conn, 404, "Not found")
      end
    else
      conn
      |> put_flash(:error, gettext("Admin access required."))
      |> redirect(to: ~p"/manage")
    end
  end

  defp content_disposition(%{"download" => value}) when value in ["1", "true"] do
    "attachment"
  end

  defp content_disposition(_params), do: "inline"
end
