<!-- @moduledoc -->

# TypedStructCtor

A TypedStruct plugin to add validating constructors to a TypedStruct module

The [TypedStruct](https://hexdocs.pm/typedstruct/TypedStruct.html) macro wraps field definitions to reduce boilerplate
needed to define elixir structs and provides a
[plugin system](https://hexdocs.pm/typedstruct/TypedStruct.Plugin.html) for clients to extend the DSL.

`TypedStructCtor` uses the `__changeset__` "reflection" function added by the plugin
[TypedStructEctoChangeset](https://hexdocs.pm/typed_struct_ecto_changeset/TypedStructEctoChangeset.html) which enables
Ecto.Changeset.cast on fields defined within the TypedStruct macro.

## Try it out in Livebook

Try the macro out in real time without having to install or write any of your own code

To get started you need a running instance of [Livebook](https://livebook.dev/)

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https://github.com/withbelay/typed_struct_ctor/blob/main/try_it_out.livemd)

## Rationale

[Ecto.Changeset](https://hexdocs.pm/ecto/Ecto.Changeset.html) is a great way to create validated
structs.  However, if you've many validated structs they quickly become "noise", where writing
these functions can be tedious, and bugs are easily introduced as struct changes are easily overlooked.
When the effort needed to write boilerplate tests for boilerplate code is factored in, it can be tempting to skip
struct validation altogether.

## Simple Examples

  ```elixir
    defmodule AStruct do
      use TypedStruct

      typedstruct do
        plugin(TypedStructEctoChangeset)
        plugin(TypedStructCtor)

        # A required field with a default value provided by MFA tuple to return a UUID
        field :id, :string, default_apply: {Ecto.UUID, :generate, []}
        
        # A required field with no default, meaning it must be provided to the constructor.
        # It's an `integer` with known `Ecto.cast` behavior, so for instance, string values are cast 
        # for example string to integer
        field :integer_field, :integer
        
        # An optional field with no default, meaning it will only have a value if provided to the 
        # constructor
        field :some_string, :string, required: false 
      end
    end

    iex()> AStruct.new(%{some_string: "foo"})
    {:error,
     #Ecto.Changeset<
       action: :new,
       changes: %{id: "36153915-bfd7-4067-85e1-03c9b0662582", some_string: "foo"},
       errors: [integer_field: {"can't be blank", [validation: :required]}],
       data: #AStruct<>,
       valid?: false
     >}

    # With `bang` notation and demonstrating Ecto's field cast (string to integer)
    iex()> AStruct.new!(%{some_string: "bar", integer_field: "42"})
    %AStruct{
      some_string: "bar",
      integer_field: 42,
      id: "2e28df41-c024-465e-901d-22c974f1d356"
    }
  ```

The TypedStruct macro makes it much easier to define structs.  The TypedStructEctoChangeset plugin uses the field
definitions to generate an Ecto.Changeset.cast function for fields in the struct.  And this plugin, TypedStructCtor,
uses those `cast` functions to generate validating constructors for the enclosing struct created by TypedStruct.

This plugin adds 5 constructors, `new/0`, `new/1`, `new!/1`, `from/2`, and `from!/2` to the given module.  
Ecto `cast` is called for all attributes provided to the constructors, defaults are applied where needed, and
validation is performed.  

The `new` functions return {:ok, struct} or {:error, changeset}, while the `new!` functions return the struct, or
raises if there were issues with `cast` or validation.

The `new` function takes an optional map of attributes, does
[Changeset.cast](https://hexdocs.pm/ecto/Ecto.Changeset.html#cast/4) of all values matching the defined
fields, adds defaults for fields missing values, validates any required fields, and finally does
[Changeset.apply_action](https://hexdocs.pm/ecto/Ecto.Changeset.html#apply_action/2) to validate the changeset.
Returns `{:ok, <struct>}` if everything is OK, `{:error, <changeset>}` if there were issues with `cast` or validation.
Because it's necessary to properly handle mappable fields, if a struct is passed to the `new` function,
`{:error, :attributes_must_be_a_map}` is returned; use one of the `from` functions for that use case as described below.

The `from` functions are useful in messaging environments where a new message is created from a some set of
values from a source message.  They are similar to the `new` functions but accept a "base struct" as the first argument 
and a map of attributes as the second argument.  The base struct is mapped first to the field values, and the attributes 
are merged on top.


## Required Fields
By default, all fields are required when calling the constructors.  Meaning you'll get a changeset error if the 
field does not have a default, and you don't provide an attribute value for it in the constructor.

You can override this by passing `required: false` to the plugin

  ```elixir
  typedstruct do
    plugin(TypedStructEctoChangeset)
    plugin(TypedStructCtor, required: false)

    field :this_field_is_not_required, :string
  end
  ```

Or by passing `required: false` to the `field` definition.

  ```elixir
  typedstruct do
    plugin(TypedStructEctoChangeset)
    plugin(TypedStructCtor)

    field :this_field_is_not_required, :string, required: false
  end
  ```

## Field-level Defaults
`default` and `default_apply` can be provided to the `field` definition to specify a default value for the field.

Though you can specify both `default` and `default_apply` (an MFA tuple), only one will be used.
`default` will be used with Elixir's struct syntax (e.g. `%AStruct{}`).
`default_apply` will be invoked when one of the 5 constructor functions is used (e.g. `AStruct.new!()`)

The `default_apply` function is short-circuited and will only be invoked if the given field was not present in the 
attributes.

  ```elixir
    defmodule AStructWithDefaulting do
      use TypedStruct

      typedstruct do
        plugin(TypedStructEctoChangeset)
        plugin(TypedStructCtor)

        field :field, :integer, default: 42, default_apply: {SomeModule, :some_function, ["55"]}
      end
    end

    iex()> %AStructWithDefaulting{}
    %AStructWithDefaulting{field: 42}

    iex()> AStructWithDefaulting.new!()
    %AStructWithDefaulting{field: 55}
  ```

## Mappable Fields

As mentioned above, when using `from` and `from!` functions, the first argument is a "source" struct whose matching-name
fields will be copied first into the struct being constructed.  By default, all matching-name fields are copied, but
the `mappable?` boolean attribute can be used to specify which fields are not copied.  This is useful when you want the
newly constructed struct to have different values for a field than the source struct such as `created_at` or `id`.

Not mapping over the source struct values will mean the newly constructed struct will leave the new fields empty
unless defaulted or provided as attributes to the constructor.

  ```elixir
    defmodule AStructWithMappableFields do
      use TypedStruct
    
      typedstruct do
        plugin(TypedStructEctoChangeset)
        plugin(TypedStructCtor)
    
        field(:id, :string, mappable?: false, default_apply: {Ecto.UUID, :generate, []})
        field(:created_at, :utc_datetime_usec, mappable?: false, default_apply: {DateTime, :utc_now, []})
        field(:reason, :string)
      end
    end

    # In the example below, the `id` and `created_at` fields are `mappable?: false` so they are not 
    # copied from the source struct.  So in the new struct, `:reason` is copied from the source 
    # struct, `:id` is provided in the attributes map, and `:created_at`, being nil after all the
    # copying is done, causes its default to be used instead, resulting in a new date.
    iex()> source_struct = AStructWithMappableFields.new!(%{reason: "because"})
    %AStructWithMappableFields{
      reason: "because",
      created_at: ~U[2023-11-18 04:57:16.754681Z],
      id: "ffe94776-5d6e-4d84-9aeb-2862d874577f"
    }
    
    iex()>  Process.sleep(5)
    iex()>  mapped = AStructWithMappableFields.from!(source_struct, %{id: "id from attributes"})
    %AStructWithMappableFields{
      reason: "because",
      created_at: ~U[2023-11-18 04:57:16.766353Z],
      id: "id from attributes"
    }

    iex()> Process.sleep(5)
    iex()> mapped = AStructWithMappableFields.from!(source_struct, %{reason: "I said so"})
    %AStructWithMappableFields{
      reason: "I said so",
      created_at: ~U[2023-11-18 04:57:16.772312Z],
      id: "a09be86b-373a-48f0-9d74-faee10037421"
    }
  ```

## String keyed attributes
The attributes map provided to the constructor functions can be either string-keyed or atom-key, not mixed.

Under the covers we are using [Ecto.Changeset.cast/4](https://hexdocs.pm/ecto/Ecto.Changeset.html#cast/4), to
copy and cast attributes into the struct being created.  

## Installation
Because this plugin supports the interface defined by the `TypedStruct` macro, installation assumes you've already
added that dependency.

While you can use the original [typed_struct](https://hex.pm/packages/typed_struct) library, it seems to no longer be
maintained.  However, there is a fork [here](https://hex.pm/packages/typedstruct) that is quite active.

The package can be installed by adding `typed_struct_ctor` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    # Choose either of the following `TypedStruct` libraries 
    # both use the same name for the macro - `typedstruct` but
    # but are mutually exclusive:
    
    # The original, but no longer maintained library
    {:typed_struct, "~> 0.3.0"},
      
    # Or the newer forked library
    {:typedstruct, "~> 0.5.2"},

    # And add this library  
    {:typed_struct_ctor, "~> 0.1.0"}
  ]
end
```
