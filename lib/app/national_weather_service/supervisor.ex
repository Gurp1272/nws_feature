defmodule App.NationalWeatherService.Supervisor do
  use Supervisor

  alias App.NationalWeatherService.Poller
  alias App.Singleton

  def start_link(poll?: poll?) do
    Singleton.Supervisor.start_link(__MODULE__, poll?, name: {:global, __MODULE__})
  end

  def init(poll?) do
    children = [
      {Poller, poll?: poll?}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
