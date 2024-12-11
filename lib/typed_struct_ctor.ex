defmodule TypedStructCtor do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- @moduledoc -->")
             |> Enum.fetch!(1)

  use TypedStruct.Plugin
  use Ecto.Schema
  import Ecto.Changeset

  defmacro init(opts) do
    quote do
      Module.register_attribute(__MODULE__, :required?, accumulate: false)
      Module.register_attribute(__MODULE__, :all_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :default_apply_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :required_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :non_mapped_fields, accumulate: true)

      globally_required = Keyword.get(unquote(opts), :required, true)
      Module.put_attribute(__MODULE__, :required?, globally_required)
    end
  end

  @doc false
  def field(name, type, opts, env) do
    quote bind_quoted: [name: name, type: Macro.escape(type), opts: Macro.escape(opts), env: Macro.escape(env)] do
      TypedStructCtor.__field__(name, type, opts, env)
    end
  end

  def __field__(name, _type, opts, %Macro.Env{module: mod}) do
    Module.put_attribute(mod, :all_fields, {name, true})

    if default_apply = Keyword.get(opts, :default_apply) do
      Module.put_attribute(mod, :default_apply_fields, {name, default_apply})
    end

    if !Keyword.get(opts, :mappable?, true) do
      Module.put_attribute(mod, :non_mapped_fields, {name, true})
    end

    globally_required = Module.get_attribute(mod, :required?)

    if Keyword.get(opts, :required, globally_required) do
      Module.put_attribute(mod, :required_fields, {name, opts})
    end
  end

  def after_definition(_opts) do
    quote unquote: false do
      def __defaults__, do: @default_apply_fields |> Enum.reverse()
      def __required__, do: @required_fields |> Keyword.keys() |> Enum.reverse()
      def __not_mapped__, do: @non_mapped_fields |> Keyword.keys() |> Enum.reverse()
      def __all__, do: @all_fields |> Keyword.keys() |> Enum.reverse()

      Module.delete_attribute(__MODULE__, :required?)
      Module.delete_attribute(__MODULE__, :all_fields)
      Module.delete_attribute(__MODULE__, :default_apply_fields)
      Module.delete_attribute(__MODULE__, :required_fields)
      Module.delete_attribute(__MODULE__, :non_mapped_fields)

      def new(), do: new(%{})

      def new(attrs), do: TypedStructCtor.do_new(__ENV__.module, attrs)

      def new!(), do: new!(%{})

      def new!(attrs) do
        case new(attrs) do
          {:ok, val} -> val
          {:error, :attributes_must_be_a_map} -> raise "Invalid #{__ENV__.module}.new!(): Attributes must be a map}"
          {:error, cs} -> raise "Invalid #{__ENV__.module}.new!(): #{inspect(cs.errors)}"
        end
      end

      def from(base_struct), do: from(base_struct, %{})

      def from(base_struct, attrs), do: TypedStructCtor.do_from(__ENV__.module, base_struct, attrs)

      def from!(base_struct), do: from!(base_struct, %{})

      def from!(base_struct, attrs) do
        case from(base_struct, attrs) do
          {:ok, val} -> val
          {:error, :attributes_must_be_a_map} -> raise "Invalid #{__ENV__.module}.from!(): Attributes must be a map}"
          {:error, cs} -> raise "Invalid #{__MODULE__}.from!(): #{inspect(cs.errors)}"
        end
      end
    end
  end

  @spec new() :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @doc "Create a new struct with default values"
  def new(), do: nil

  @spec new(attrs :: map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @doc """
  Create a new struct where values from keys in the provided attributes map are copied
  to like-named fields in the struct.

  * Provided values will be cast to the appropriate field type.
  * Fields in the newly constructed struct that are not in the provided map will
    be set to their default values.
  * Required fields that are nil will result in a Ecto.Changeset error
  """
  def new(_attrs), do: nil

  @spec new!() :: struct()
  @doc "Create a new struct with default values.  Raises if the new struct cannot be validated."
  def new!(), do: nil

  @spec new!(attrs :: map()) :: struct()
  @doc """
  Create a new struct where values from keys in the provided attributes map are copied
  to like-named fields in the struct.  Raises if the new struct cannot be validated.

  * Provided values will be cast to the appropriate field type.
  * Fields in the newly constructed struct that are not in the provided map will
    be set to their default values.
  * Any cast error or missing required field will result in a raise
  """
  def new!(_attrs), do: nil

  @spec from(base_struct :: struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @doc """
  Create a new struct where values from fields in the provided struct are copied.

  The `from/1` constructor is useful for event driven systems where it is common to create
  a new event from a given "triggering" event

  * Provided values from `base_struct` will be cast to the appropriate field type.
  * Fields in the newly constructed struct that are not provided map will
    be set to their default values.
  * Required fields that are nil will result in a Ecto.Changeset error
  """
  def from(_base_struct), do: nil

  @spec from(base_struct :: struct(), attrs :: map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @doc """
  Create a new struct where values from fields in the provided struct are copied, then values
  from the provided attributes map are copied to like-named fields in the struct; overwriting
  any values copied from the base_struct.

  The `from/2` constructor is useful for event driven systems where it is common to create
  a new event from a given "triggering" event

  * Provided values from `base_struct` will be cast to the appropriate field type.
  * Fields in the newly constructed struct that are not provided map will
    be set to their default values.
  * Required fields that are nil will result in a Ecto.Changeset error
  """
  def from(_base_struct, _attrs), do: nil

  @spec from!(base_struct :: struct()) :: struct()
  @doc """
  Create a new struct where values from fields in the provided struct are copied.  Raising if the new struct
  cannot be validated.

  The `from!/1` constructor is useful for event driven systems where it is common to create
  a new event from a given "triggering" event

  * Provided values from `base_struct` will be cast to the appropriate field type.
  * Fields in the newly constructed struct that are not provided map will
    be set to their default values.
  * Any cast error or missing required field will result in a `raise`
  """
  def from!(_base_struct), do: nil

  @spec from!(base_struct :: struct(), attrs :: map()) :: struct()
  @doc """
  Create a new struct where values from fields in the provided struct are copied, then values
  from the provided attributes map are copied to like-named fields in the struct; overwriting
  any values copied from the base_struct.  Raising if the new struct cannot be validated.

  The `from!/2` constructor is useful for event driven systems where it is common to create
  a new event from a given "triggering" event

  * Provided values from `base_struct` will be cast to the appropriate field type.
  * Fields in the newly constructed struct that are not provided map will
    be set to their default values.
  * Any cast error or missing required field will result in a `raise`
  """
  def from!(_base_struct, _attrs), do: nil

  @doc false
  def do_new(mod, attrs) when not is_struct(attrs) and is_map(attrs) do
    mod.__struct__()
    |> cast(attrs, mod.__all__())
    |> TypedStructCtor.apply_defaults(mod.__defaults__())
    |> validate_required(mod.__required__())
    |> apply_action(:new)
  end

  def do_new(_mod, _attrs), do: {:error, :attributes_must_be_a_map}

  @doc false
  def do_from(mod, base_struct, attrs) when is_struct(base_struct) do
    # `attrs` could be string-keyed map, use Ecto to convert to validated atom-keys
    case cast(mod.__struct__(), attrs, mod.__all__(), force_changes: true) do
      %{valid?: true, changes: valid_attrs} ->
        merged_attrs =
          base_struct
          |> Map.from_struct()
          |> Map.drop(mod.__not_mapped__())
          |> Map.merge(valid_attrs)

        TypedStructCtor.do_new(mod, merged_attrs)

      other ->
        other
    end
  end

  def do_from(_mod, _base_struct, _attrs), do: {:error, :base_struct_must_be_a_struct}

  # For each field that has a default_apply, apply the result of that function IF the field is not already changed/set
  @doc false
  def apply_defaults(%Ecto.Changeset{} = changeset, defaults) do
    apply_default = fn
      {m, f, a} -> apply(m, f, a)
      {f, a} -> apply(f, a)
    end

    Enum.reduce(defaults, changeset, fn {field, apply}, changeset ->
      if get_change(changeset, field) == nil do
        defaulted_value = apply_default.(apply)
        cast(changeset, %{field => defaulted_value}, [field])
      else
        changeset
      end
    end)
  end
end
