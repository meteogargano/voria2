defmodule Voria2Web.WebcamJumpLiveTest do
  use Voria2Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Voria2.MeasurementsHelpers

  setup do
    Application.put_env(:voria2, :storage_public_endpoint, "https://media.test")

    user = create_user()
    installation = create_installation(user)
    webcam = create_webcam(installation)

    earlier =
      create_shot(
        webcam,
        ~U[2026-04-21 23:58:00Z],
        "webcams/#{webcam.id}/earlier.webp",
        "hash-earlier"
      )

    same_day =
      create_shot(
        webcam,
        ~U[2026-04-22 12:04:00Z],
        "webcams/#{webcam.id}/same-day.webp",
        "hash-same-day"
      )

    next_day =
      create_shot(
        webcam,
        ~U[2026-04-23 00:02:00Z],
        "webcams/#{webcam.id}/next-day.webp",
        "hash-next-day"
      )

    %{
      webcam: webcam,
      earlier: earlier,
      same_day: same_day,
      next_day: next_day
    }
  end

  describe "WebcamViewerLive jump search" do
    test "selects the closest shot on submit", %{conn: conn, webcam: webcam, same_day: same_day} do
      {:ok, view, _html} = live(conn, ~p"/webcams/#{webcam.id}/viewer")

      assert has_element?(view, "#webcam-jump-form")

      view
      |> element("#webcam-jump-form")
      |> render_submit(%{
        "jump" => %{
          "input" => "22/04/2026 12:03",
          "utc_iso" => "2026-04-22T12:03:00Z"
        }
      })

      assert has_element?(view, "#webcam-shot-image[src='#{expected_url(same_day)}']")
      refute has_element?(view, "#webcam-jump-error")
    end

    test "can jump across day boundaries to the nearest shot", %{
      conn: conn,
      webcam: webcam,
      next_day: next_day
    } do
      {:ok, view, _html} = live(conn, ~p"/webcams/#{webcam.id}/viewer")

      view
      |> element("#webcam-jump-form")
      |> render_submit(%{
        "jump" => %{
          "input" => "23/04/2026 00:01",
          "utc_iso" => "2026-04-23T00:01:00Z"
        }
      })

      assert has_element?(view, "#webcam-shot-image[src='#{expected_url(next_day)}']")
    end

    test "shows an error for invalid datetime input", %{conn: conn, webcam: webcam} do
      {:ok, view, _html} = live(conn, ~p"/webcams/#{webcam.id}/viewer")

      view
      |> element("#webcam-jump-form")
      |> render_submit(%{
        "jump" => %{
          "input" => "bad input",
          "utc_iso" => ""
        }
      })

      assert has_element?(view, "#webcam-jump-error")
      assert has_element?(view, "#webcam-jump-input[value='bad input']")
    end
  end

  describe "WebcamsLive jump search" do
    test "shows the jump bar on the index page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/webcams")

      assert has_element?(view, "#webcams-grid-jump-form")
      assert has_element?(view, "#webcams-grid-jump-webcam")
      assert has_element?(view, "#webcams-grid-jump-input")
      assert has_element?(view, "#webcams-grid-jump-submit")
    end

    test "selects the closest shot in the modal viewer route", %{
      conn: conn,
      webcam: webcam,
      same_day: same_day
    } do
      {:ok, view, _html} = live(conn, ~p"/webcams/#{webcam.id}")

      assert has_element?(view, "#webcams-jump-form")

      view
      |> element("#webcams-jump-form")
      |> render_submit(%{
        "jump" => %{
          "input" => "22/04/2026 12:03",
          "utc_iso" => "2026-04-22T12:03:00Z"
        }
      })

      assert has_element?(view, "#webcams-shot-image[src='#{expected_url(same_day)}']")
      refute has_element?(view, "#webcams-jump-error")
    end

    test "shows an error for invalid datetime input in modal viewer", %{
      conn: conn,
      webcam: webcam
    } do
      {:ok, view, _html} = live(conn, ~p"/webcams/#{webcam.id}")

      view
      |> element("#webcams-jump-form")
      |> render_submit(%{
        "jump" => %{
          "input" => "bad input",
          "utc_iso" => ""
        }
      })

      assert has_element?(view, "#webcams-jump-error")
      assert has_element?(view, "#webcams-jump-input[value='bad input']")
    end

    test "index jump redirects to the selected webcam and nearest shot", %{
      conn: conn,
      webcam: webcam,
      same_day: same_day
    } do
      {:ok, view, _html} = live(conn, ~p"/webcams")

      view
      |> element("#webcams-grid-jump-form")
      |> render_submit(%{
        "jump" => %{
          "webcam_id" => webcam.id,
          "input" => "22/04/2026 12:03",
          "utc_iso" => "2026-04-22T12:03:00Z"
        }
      })

      assert_patch(
        view,
        ~p"/webcams/#{webcam.id}?#{%{jump_input: "22/04/2026 12:03", utc_iso: "2026-04-22T12:03:00Z"}}"
      )

      assert has_element?(view, "#webcams-shot-image[src='#{expected_url(same_day)}']")
    end
  end

  defp create_shot(webcam, captured_at, s3_key, hash) do
    {:ok, shot} =
      Voria2.Network.record_webcam_shot(
        %{
          webcam_id: webcam.id,
          captured_at: captured_at,
          s3_key: s3_key,
          s3_bucket: "voria2-media",
          original_hash: hash,
          width: 1280,
          height: 720,
          file_size_bytes: 1024
        },
        authorize?: false
      )

    shot
  end

  defp expected_url(shot), do: "https://media.test/#{shot.s3_key}"
end
