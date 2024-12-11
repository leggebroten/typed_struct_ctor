defmodule SomeModule do
  def some_function(value) do
    existing = Process.get(:some_function, [])
    Process.put(:some_function, [value | existing])
    value
  end
end

defmodule AStruct do
  use TypedStruct

  typedstruct do
    plugin(TypedStructEctoChangeset)
    plugin(TypedStructCtor, required: false)

    field(:not_required_defaulted, :integer, default_apply: {SomeModule, :some_function, ["42"]})
    field(:not_required_not_defaulted, :integer)

    field(:required_defaulted, :integer,
      required: true,
      default_apply: {SomeModule, :some_function, ["43"]}
    )

    field(:required_not_defaulted, :integer, required: true)
  end
end

defmodule AStructGloballyRequired do
  use TypedStruct

  typedstruct do
    plugin(TypedStructEctoChangeset)
    plugin(TypedStructCtor)

    field(:not_required_defaulted, :string,
      required: false,
      default_apply: {SomeModule, :some_function, ["bar"]}
    )

    field(:not_required_not_defaulted, :string, required: false)
    field(:required_defaulted, :string, default_apply: {SomeModule, :some_function, ["foo"]})
    field(:required_not_defaulted, :string)
  end
end

defmodule Mappable do
  use TypedStruct

  typedstruct do
    plugin(TypedStructEctoChangeset)
    plugin(TypedStructCtor)

    field(:defaulted, :string, default: "defaulted")
    field(:mapped_by_default, :string, default: "bar")
    field(:id, :string, mappable?: false, default_apply: {Ecto.UUID, :generate, []})
  end
end

defmodule TypedStructCtorTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "when attributes supplied, use them" do
      assert {:ok,
              %AStruct{
                not_required_defaulted: 1,
                not_required_not_defaulted: 2,
                required_defaulted: 3,
                required_not_defaulted: 4
              }} ==
               AStruct.new(%{
                 not_required_defaulted: "1",
                 not_required_not_defaulted: "2",
                 required_defaulted: "3",
                 required_not_defaulted: "4"
               })
    end

    test "when attributes are string keys, map to atoms" do
      assert {:ok,
              %AStruct{
                not_required_defaulted: 1,
                not_required_not_defaulted: 2,
                required_defaulted: 3,
                required_not_defaulted: 4
              }} ==
               AStruct.new(%{
                 "not_required_defaulted" => "1",
                 "not_required_not_defaulted" => "2",
                 "required_defaulted" => "3",
                 "required_not_defaulted" => "4"
               })
    end

    test "when no attributes supplied, use defaults" do
      assert {:error, message} = AStruct.new(%{})

      assert %{not_required_defaulted: 42, required_defaulted: 43} == message.changes

      assert [
               required_not_defaulted: {"can't be blank", [validation: :required]}
             ] == message.errors
    end

    test "when attribute supplied for a defaulted field, do NOT invoke the field's default function" do
      assert {:ok, %{required_defaulted: 43}} = AStruct.new(%{required_not_defaulted: 46})

      # Show that the default function was invoked
      assert Process.get(:some_function) == ["43", "42"]

      # Delete the key from process memory
      Process.delete(:some_function)
      refute :some_function in Process.get_keys()

      # Now create but with a value for the defaulted field
      assert {:ok, %{required_defaulted: 45}} = AStruct.new(%{required_defaulted: 45, required_not_defaulted: 46})

      # Show that the default function was NOT invoked
      assert Process.get(:some_function) == ["42"]
    end

    test "when a struct is provided, return error tuple. They should use `from` instead" do
      {:ok, msg} = AStruct.new(%{required_not_defaulted: "4"})

      assert {:error, :attributes_must_be_a_map} == AStruct.new(msg)
    end
  end

  describe "new!/1" do
    test "when no errors, return created struct" do
      assert %AStruct{
               required_not_defaulted: 4,
               required_defaulted: 3,
               not_required_not_defaulted: 2,
               not_required_defaulted: 1
             } ==
               AStruct.new!(%{
                 not_required_defaulted: "1",
                 not_required_not_defaulted: 2,
                 required_defaulted: "3",
                 required_not_defaulted: 4
               })
    end

    test "when errors occur, raises" do
      assert_raise(
        RuntimeError,
        "Invalid Elixir.AStruct.new!(): [required_not_defaulted: {\"can't be blank\", [validation: :required]}]",
        fn -> AStruct.new!(%{}) end
      )
    end
  end

  describe "new/0" do
    test "when no attributes supplied, use defaults" do
      assert {:error, message} = AStruct.new()

      assert %{not_required_defaulted: 42, required_defaulted: 43} == message.changes

      assert [
               required_not_defaulted: {"can't be blank", [validation: :required]}
             ] == message.errors
    end

    test "when globally required, can be overridden on field" do
      assert {:error, message} = AStructGloballyRequired.new()

      assert %{not_required_defaulted: "bar", required_defaulted: "foo"} == message.changes

      assert [
               required_not_defaulted: {"can't be blank", [validation: :required]}
             ] == message.errors
    end
  end

  describe "new!/0" do
    test "when no attributes supplied, use defaults" do
      assert %AStruct{
               required_not_defaulted: 87,
               required_defaulted: 43,
               not_required_not_defaulted: nil,
               not_required_defaulted: 42
             } == AStruct.new!(%{required_not_defaulted: 87})
    end

    test "when errors occur, raises" do
      assert_raise(
        RuntimeError,
        "Invalid Elixir.AStruct.new!(): [required_not_defaulted: {\"can't be blank\", [validation: :required]}]",
        fn -> AStruct.new!() end
      )
    end
  end

  describe "from/2" do
    test "when source struct has field with same name but destination is not `mappable?`, don't copy" do
      original_struct = Mappable.new!(%{mapped_by_default: "foo"})
      {:ok, mapped_struct} = Mappable.from(original_struct, %{mapped_by_default: "bar"})

      assert mapped_struct.mapped_by_default == "bar"

      refute original_struct.id == mapped_struct.id
    end

    test "when attributes have value for not-mapped fields, it's used" do
      original_struct = Mappable.new!(%{mapped_by_default: "foo"})
      {:ok, mapped_struct} = Mappable.from(original_struct, %{id: "baz"})

      assert mapped_struct.id == "baz"
    end

    test "when attributes have string keys, they're cast correctly as atom keys" do
      original_struct = Mappable.new!(%{"mapped_by_default" => "foo"})

      {:ok, %{id: "baz", mapped_by_default: "bar"}} =
        Mappable.from(original_struct, %{"id" => "baz", "mapped_by_default" => "bar"})

      {:ok, %{id: "baz", mapped_by_default: "foo"}} = Mappable.from(original_struct, %{"id" => "baz"})

      {:ok, %{id: id, mapped_by_default: "foo"}} = Mappable.from(original_struct)
      refute id == original_struct.id
      {:ok, _uuid} = Ecto.UUID.cast(id)
    end

    test "when fails validation, return error tuple" do
      original_struct = Mappable.new!(%{mapped_by_default: "foo"})
      {:error, changeset} = Mappable.from(original_struct, %{mapped_by_default: nil})
      assert changeset.errors == [mapped_by_default: {"can't be blank", [validation: :required]}]
    end
  end

  describe "from!/2" do
    test "when source struct has field with same name but destination is not `mappable?`, don't copy" do
      original_struct = Mappable.new!(%{mapped_by_default: "foo"})
      mapped_struct = Mappable.from!(original_struct, %{mapped_by_default: "bar"})

      assert mapped_struct.mapped_by_default == "bar"

      refute original_struct.id == mapped_struct.id
    end

    test "when attributes have value for not-mapped fields, it's used" do
      original_struct = Mappable.new!(%{mapped_by_default: "foo"})
      mapped_struct = Mappable.from!(original_struct, %{id: "baz"})

      assert mapped_struct.id == "baz"
    end

    test "when fails validation, raises" do
      original_struct = Mappable.new!(%{mapped_by_default: "foo"})

      assert_raise(
        RuntimeError,
        "Invalid Elixir.Mappable.from!(): [mapped_by_default: {\"can't be blank\", [validation: :required]}]",
        fn -> Mappable.from!(original_struct, %{mapped_by_default: nil}) end
      )
    end
  end

  describe "casting" do
    defmodule AStructWithCasting do
      use TypedStruct

      typedstruct do
        plugin(TypedStructEctoChangeset)
        plugin(TypedStructCtor)

        field(:field, :integer, default_apply: {SomeModule, :some_function, ["5"]})
      end
    end

    test "when provided value on construction, make sure it's cast" do
      assert %AStructWithCasting{field: 5} == AStructWithCasting.new!(%{field: "5"})
    end

    test "when defaulted, make sure it's cast" do
      assert %AStructWithCasting{field: 5} == AStructWithCasting.new!()
    end
  end

  describe "elixir defaults" do
    defmodule AStructWithDefaulting do
      use TypedStruct

      typedstruct do
        plugin(TypedStructEctoChangeset)
        plugin(TypedStructCtor)

        field(:field_1, :integer, default_apply: {SomeModule, :some_function, ["5"]})

        field(:field_2, :integer, default: 42, default_apply: {SomeModule, :some_function, ["55"]})

        field(:field_3, :integer, default: 43)
      end
    end

    test "struct has elixir defaults" do
      assert %AStructWithDefaulting{} == %AStructWithDefaulting{
               field_1: nil,
               field_2: 42,
               field_3: 43
             }
    end
  end

  describe "supporting field as an array" do
    defmodule WithArray do
      use TypedStruct

      typedstruct do
        plugin(TypedStructEctoChangeset)
        plugin(TypedStructCtor)

        field(:field_1, [:integer], default_apply: {SomeModule, :some_function, [["5", "6"]]})
        field(:field_2, [:integer], default_apply: {SomeModule, :some_function, ["42"]})
      end
    end

    test "when provided an array, casts each element of the array" do
      assert %WithArray{field_2: [1, 2], field_1: [5, 6]} ==
               WithArray.new!(%{field_2: ["1", "2"]})
    end
  end
end
