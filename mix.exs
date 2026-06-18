defmodule FactorialHREx.MixProject do
  use Mix.Project

  def project do
    [
      app: :factorial_hr_ex,
      version: "0.1.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/Balneario-de-Cofrentes/factorial_hr_ex",
      homepage_url: "https://github.com/Balneario-de-Cofrentes/factorial_hr_ex",
      docs: [
        main: "FactorialHREx",
        source_ref: "v0.1.1",
        extras: ["README.md", "CHANGELOG.md", "LICENSE", "CONTRIBUTING.md", "SECURITY.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:plug, "~> 1.17", only: :test},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Small, framework-agnostic Elixir client for the public Factorial HR REST API."
  end

  defp package do
    [
      name: "factorial_hr_ex",
      files: [
        "lib",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "SECURITY.md"
      ],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/Balneario-de-Cofrentes/factorial_hr_ex",
        "Factorial API Docs" => "https://apidoc.factorialhr.com"
      },
      maintainers: ["Balneario de Cofrentes"]
    ]
  end
end
