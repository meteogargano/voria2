defmodule Voria2.Measurements.MeasurementTypeTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  describe "CRUD" do
    test "create and read" do
      user = create_user()
      n = System.unique_integer([:positive])

      assert {:ok, mt} =
               Measurements.create_measurement_type(
                 %{name: "Temp", slug: "temp-#{n}", storage_type: :scalar},
                 authorize?: false
               )

      assert mt.slug == "temp-#{n}"
      assert {:ok, found} = Measurements.get_measurement_type(mt.id, authorize?: false)
      assert found.id == mt.id
    end

    test "update" do
      user = create_user()
      mt = create_measurement_type(user_id: user.id)

      assert {:ok, updated} =
               Measurements.update_measurement_type(mt, %{name: "Updated"}, actor: user)

      assert updated.name == "Updated"
    end

    test "destroy" do
      user = create_user()
      mt = create_measurement_type(user_id: user.id)
      assert :ok = Measurements.destroy_measurement_type(mt, actor: user)
    end
  end

  describe "is_system_defined calculation" do
    test "nil user_id -> true" do
      mt = create_measurement_type(user_id: nil)
      loaded = Ash.load!(mt, [:is_system_defined], authorize?: false)
      assert loaded.is_system_defined == true
    end

    test "with user_id -> false" do
      user = create_user()
      mt = create_measurement_type(user_id: user.id)
      loaded = Ash.load!(mt, [:is_system_defined], authorize?: false)
      assert loaded.is_system_defined == false
    end
  end

  describe "unit immutability on system types" do
    test "changing unit on a system type (user_id nil) is rejected even without auth" do
      mt = create_measurement_type(user_id: nil)

      assert {:error, %Ash.Error.Invalid{}} =
               Measurements.update_measurement_type(mt, %{unit: "°F"}, authorize?: false)
    end

    test "changing name/description on a system type is allowed" do
      mt = create_measurement_type(user_id: nil)

      assert {:ok, updated} =
               Measurements.update_measurement_type(mt, %{name: "Renamed", description: "desc"},
                 authorize?: false
               )

      assert updated.name == "Renamed"
    end

    test "admin cannot change unit on a system type" do
      admin = create_admin()
      mt = create_measurement_type(user_id: nil)

      assert {:error, %Ash.Error.Invalid{}} =
               Measurements.update_measurement_type(mt, %{unit: "°F"}, actor: admin)
    end

    test "owner can change unit on a user-defined type" do
      user = create_user()
      mt = create_measurement_type(user_id: user.id)

      assert {:ok, updated} =
               Measurements.update_measurement_type(mt, %{unit: "ppb"}, actor: user)

      assert updated.unit == "ppb"
    end
  end

  describe "policies" do
    test "user can create their own type" do
      user = create_user()
      n = System.unique_integer([:positive])

      assert {:ok, _} =
               Measurements.create_measurement_type(
                 %{name: "My Type", slug: "my-type-#{n}", storage_type: :scalar},
                 actor: user
               )
    end

    test "user cannot update system type (nil user_id)" do
      mt = create_measurement_type(user_id: nil)
      user = create_user()

      assert {:error, %Ash.Error.Forbidden{}} =
               Measurements.update_measurement_type(mt, %{name: "Hack"}, actor: user)
    end

    test "user cannot update another user's type" do
      owner = create_user()
      other = create_user()
      mt = create_measurement_type(user_id: owner.id)

      assert {:error, %Ash.Error.Forbidden{}} =
               Measurements.update_measurement_type(mt, %{name: "X"}, actor: other)
    end

    test "admin can update any type" do
      admin = create_admin()
      mt = create_measurement_type(user_id: nil)

      assert {:ok, _} =
               Measurements.update_measurement_type(mt, %{name: "Admin Updated"}, actor: admin)
    end
  end
end
