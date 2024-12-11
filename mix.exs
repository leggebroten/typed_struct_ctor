defmodule TypedStructCtor.MixProject do
  use Mix.Project

  def project do
    [
      app: :typed_struct_ctor,
      version: "0.1.2",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "TypedStructCtor",
      docs: [
        main: "TypedStructCtor",
        extras: [
          "README.md",
          "LICENSE.md": [title: "License"]
        ]
      ]
    ]
  end

  def application do
    []
  end

  defp description() do
    """
    A `TypedStruct` plugin utilizing Ecto.Changeset validation enabled by the plugin `TypedStructEctoChangeset` to
    provide validating constructors"
    """
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/withbelay/typed_struct_ctor"}
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.10"},
      {:ex_doc, "~> 0.30", only: :dev},
      {:typedstruct, "~> 0.5.2"},
      {:typed_struct_ecto_changeset, "~> 1.0.0"}
    ]
  end
end
