defmodule Voria2Web.ManageWebcamShotPurgeLiveTest do
  use Voria2Web.ConnCase, async: false

  import AshAuthentication.Plug.Helpers, only: [store_in_session: 2]
  import Phoenix.LiveViewTest
  import Voria2.MeasurementsHelpers

  setup %{conn: conn} do
    start_supervised!({Voria2.Network.WebcamShotPurger, []})

    admin = create_admin()
    user = create_user()

    installation =
      create_installation(admin, name: "Admin Purge Installation")
      |> Ash.Changeset.for_update(:update, %{city: "Bergamo", country: "Italy"})
      |> Ash.update!(authorize?: false)

    other_installation =
      create_installation(admin, name: "Other Purge Installation")
      |> Ash.Changeset.for_update(:update, %{city: "Lecco", country: "Italy"})
      |> Ash.update!(authorize?: false)

    webcam_a = create_webcam(installation, name: "North Cam")
    webcam_b = create_webcam(other_installation, name: "South Cam")

    create_shot!(webcam_a, ~U[2026-04-20 09:00:00Z], "one")
    create_shot!(webcam_a, ~U[2026-04-20 11:00:00Z], "two")
    create_shot!(webcam_b, ~U[2026-04-20 10:00:00Z], "three")

    conn = log_in(conn, admin)

    %{conn: conn, admin: admin, user: user, webcam_a: webcam_a, webcam_b: webcam_b}
  end

  test "non-admin users are redirected away from the page", %{user: user} do
    Gettext.put_locale(Voria2Web.Gettext, "en")
    conn = Phoenix.ConnTest.build_conn() |> log_in(user)

    assert {:error, {:live_redirect, %{to: "/manage", flash: flash}}} =
             live(conn, ~p"/manage/webcam-shots/purge")

    assert flash["error"] in ["Admin access required.", "Accesso admin richiesto."]
  end

  test "counts matching shots across multiple webcams", %{
    conn: conn,
    webcam_a: webcam_a,
    webcam_b: webcam_b
  } do
    {:ok, view, _html} = live(conn, ~p"/manage/webcam-shots/purge")

    view
    |> element("input[phx-click='toggle_webcam'][phx-value-id='#{webcam_a.id}']")
    |> render_click()

    view
    |> element("input[phx-click='toggle_webcam'][phx-value-id='#{webcam_b.id}']")
    |> render_click()

    view
    |> element("#webcam-shot-purge-form")
    |> render_submit(%{
      "filters" => %{
        "from_input" => "20/04/2026 08:00",
        "from_utc_iso" => "2026-04-20T08:00:00Z",
        "to_input" => "20/04/2026 11:00",
        "to_utc_iso" => "2026-04-20T11:00:00Z"
      }
    })

    assert has_element?(view, "#webcam-shot-purge-count", "3")
    refute has_element?(view, "#webcam-shot-purge-error")
  end

  test "starts a purge and reports progress until completion", %{conn: conn, webcam_a: webcam_a} do
    Gettext.put_locale(Voria2Web.Gettext, "en")
    Voria2.Network.WebcamShotPurger.subscribe()

    {:ok, view, _html} = live(conn, ~p"/manage/webcam-shots/purge")

    view
    |> element("input[phx-click='toggle_webcam'][phx-value-id='#{webcam_a.id}']")
    |> render_click()

    view
    |> element("#webcam-shot-purge-form")
    |> render_change(%{
      "filters" => %{
        "from_input" => "20/04/2026 08:00",
        "from_utc_iso" => "2026-04-20T08:00:00Z",
        "to_input" => "20/04/2026 12:00",
        "to_utc_iso" => "2026-04-20T12:00:00Z"
      }
    })

    render_submit(element(view, "#webcam-shot-purge-confirm-form"), %{
      "filters" => %{
        "from_input" => "20/04/2026 08:00",
        "from_utc_iso" => "2026-04-20T08:00:00Z",
        "to_input" => "20/04/2026 12:00",
        "to_utc_iso" => "2026-04-20T12:00:00Z"
      }
    })

    assert_receive {:webcam_shot_purger, %{status: :running, total: 2}}, 1_000
    assert_receive {:webcam_shot_purger, %{status: :completed, processed: 2, deleted: 2}}, 2_000

    html = render(view)
    assert has_element?(view, "#purge-status")
    assert has_element?(view, "#purge-total", "2")
    assert has_element?(view, "#purge-processed", "2")
    assert has_element?(view, "#purge-deleted", "2")
    assert has_element?(view, "#purge-failed", "0")

    assert Voria2.Network.count_webcam_shots_in_range!(
             [webcam_a.id],
             ~U[2026-04-20 08:00:00Z],
             ~U[2026-04-20 12:00:00Z]
           ) == 0
  end

  defp create_shot!(webcam, captured_at, suffix) do
    {:ok, shot} =
      Voria2.Network.record_webcam_shot(
        %{
          webcam_id: webcam.id,
          captured_at: captured_at,
          s3_key: "webcams/#{webcam.id}/#{suffix}.webp",
          s3_bucket: "voria2-media",
          original_hash: "#{webcam.id}-#{suffix}",
          width: 100,
          height: 100,
          file_size_bytes: 1024
        },
        authorize?: false
      )

    shot
  end

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user, %{"purpose" => "user"})

    conn
    |> Plug.Test.init_test_session(%{})
    |> store_in_session(Ash.Resource.put_metadata(user, :token, token))
  end
end
