defmodule Ghoul.Mixfile do
  use Mix.Project

  def project do
    [app: :ghoul,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger],
     mod: {Ghoul.Application, []}]
  end

  defp deps do
    [
      {:gproc, "~> 0.6"},
      {:pattern_tap, "~> 0.4"},
      {:shorter_maps, "~> 2.2"},
    ]
  end
end
