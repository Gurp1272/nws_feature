defmodule App.NationalWeatherService.Poller do
  @moduledoc """
  Initiates update for data in weather_table for each distinct h3_index from the properties table
  """

  use GenServer

  import Ecto.Query

  require Logger

  alias App.Repo
  alias App.NationalWeatherService.API
  alias App.NationalWeatherService.Schema.WeatherForecast
  alias App.Schema.Property

  @poll_interval 9 * 60 * 1000

  defmodule State do
    defstruct ~w[poll?]a
  end

  def start_link(poll?: poll?) do
    GenServer.start_link(__MODULE__, poll?, name: __MODULE__)
  end

  def init(poll?) do
    {:ok, %State{poll?: poll?}, {:continue, :poll}}
  end

  def handle_continue(:poll, %State{poll?: true} = state) do
    Logger.info("Running weather polling...")
    process_indexes()
    Process.send_after(self(), :poll, @poll_interval)
    Logger.info("Weather polling done")
    {:noreply, state, :hibernate}
  end

  def handle_continue(:poll, state), do: {:noreply, state}

  def handle_info(:poll, state), do: {:noreply, state, {:continue, :poll}}

  defp process_indexes() do
    fetch_distinct_h3_indexes_non_existent_in_forecast_table()
    |> Enum.each(fn index ->
      API.new_weather_forecast(index)
      :timer.sleep(1000)
    end)

    fetch_expired_forecasts()
    |> Enum.each(fn forecast ->
      API.update_weather_forecast(forecast)
      :timer.sleep(1000)
    end)
  end

  defp fetch_distinct_h3_indexes_non_existent_in_forecast_table() do
    query =
      from p in Property,
        as: :property,
        where:
          not exists(
            from(f in WeatherForecast, where: parent_as(:property).h3_index == f.h3_index)
          ),
        distinct: true,
        select: p.h3_index

    Repo.all(query)
  end

  defp fetch_expired_forecasts() do
    date =
      DateTime.utc_now()
      |> DateTime.add(@poll_interval, :millisecond)

    query = from f in WeatherForecast, where: f.expires <= ^date

    Repo.all(query)
  end
end
