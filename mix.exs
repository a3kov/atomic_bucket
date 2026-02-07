defmodule AtomicBucket.MixProject do
  use Mix.Project

  @source_url "https://github.com/a3kov/atomic_bucket"

  def project do
    [
      app: :atomic_bucket,
      version: "0.1.1",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @source_url,
      # Hex
      description: "Fast single node rate limiter implementing Token Bucket algorithm.",
      package: [
        files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE),
        licenses: ["Apache-2.0"],
        links: %{
          "GitHub" => @source_url,
          "Changelog" => "https://hexdocs.pm/atomic_bucket/changelog.html"
        }
      ],
      # Docs
      docs: [
        main: "readme",
        logo: "assets/docs_logo.png",
        extras: ["README.md", "CHANGELOG.md"]
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
      {:benchee, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end
end
