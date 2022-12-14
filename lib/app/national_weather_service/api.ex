defmodule App.NationalWeatherService.API do
  @type h3_index() :: non_neg_integer()

  @moduledoc """
  API for National Weather Service
  """

  import Ecto.Query

  require Logger

  alias Frontline.Repo
  alias Frontline.Schema.Property
  alias Frontline.{AirQuality, WildfireCondition, FireDanger}
  alias Frontline.NationalWeatherService.Schema.WeatherForecast
  alias Frontline.NationalWeatherService.{Client, Conditions}

  @doc """
  Meant to only receive indexes that aren't currently present in the weather_forecast table

  Creates a new record in the weather_forecast table
  """
  @spec new_weather_forecast(h3_index()) ::
          {:ok, WeatherForecast.t()} | {:error, Ecto.Changeset.t()}
  def new_weather_forecast(h3_index) do
    case :h3.is_valid(h3_index) do
      false -> Logger.error("Invalid h3_index: #{h3_index}")
      true -> fetch_new_forecast(h3_index)
    end
  end

  @doc """
  Receives a weather forecast record and updates it with current information
  """
  @spec update_weather_forecast(WeatherForecast.t()) ::
          {:ok, WeatherForecast.t()} | {:error, Ecto.Changeset.t()}
  def update_weather_forecast(
        %WeatherForecast{nws_grid_id: id, nws_grid_x: x, nws_grid_y: y} = forecast
      ) do
    Client.query_grid_forecast(id, x, y)
    |> update_forecast(forecast)
  end

  @doc """
  Queries for data within datetime range from forecast column of the weather_forecasts table

  Returns a list of %Conditions{}
  """
  @spec forecast(Property.t(), DateTime.t(), DateTime.t()) :: {:ok, List.t(Conditions.t())} | []
  def forecast(%Property{h3_index: h3_index} = property, start_time, end_time) do
    {:ok,
     case fetch_weather_forecast(h3_index) do
       %WeatherForecast{forecast: forecasts} ->
         forecasts
         |> forecasts_in_range(start_time, end_time)
         |> Enum.map(&build_conditions_struct(&1, property))

       _ ->
         [build_conditions_struct({start_time, %{}}, property)]
     end}
  end

  @doc """
  Queries for most recent data within forecast column of the weather_forecasts table

  Returns a %Conditions{}
  """
  @spec current_forecast(Property.t(), DateTime.t() | nil) :: Conditions.t()
  def current_forecast(property, dt \\ nil)

  def current_forecast(property, dt) when is_nil(dt) do
    now = DateTime.utc_now()
    current_forecast(property, now)
  end

  def current_forecast(property, dt) do
    one_hour = DateTime.add(dt, 3600, :second)
    {:ok, [f | _]} = forecast(property, dt, one_hour)
    f
  end

  defp build_conditions_struct({datetime, forecast}, property) do
    grid_code = FireDanger.API.for_property(property)
    aqi = AirQuality.API.for_property(property)
    keys = Map.keys(%Conditions{}) |> Enum.map(&to_string/1)

    forecast =
      Enum.reduce(forecast, %{}, fn {k, v}, acc ->
        key = k |> Macro.underscore()

        if key in keys do
          Map.put(acc, String.to_existing_atom(key), v)
        else
          acc
        end
      end)

    condition =
      struct(Conditions, forecast)
      |> Map.put(:id, property.h3_index)
      |> Map.put(:fire_warning_index, grid_code)
      |> Map.put(:epa_index, aqi)
      |> Map.put(:datetime, datetime)

    case WildfireCondition.API.vteccode(property) do
      "FWW" -> %Conditions{condition | red_flag_warning: true}
      "FWA" -> %Conditions{condition | fire_weather_watch: true}
      _ -> condition
    end
  end

  defp forecasts_in_range(forecasts, start_time, end_time) do
    forecasts
    |> Enum.map(fn {dt, data} ->
      {:ok, d, _} = DateTime.from_iso8601(dt)
      {d, data}
    end)
    |> Enum.filter(fn {dt, _data} ->
      with :gt <- DateTime.compare(dt, start_time),
           :lt <- DateTime.compare(dt, end_time) do
        true
      else
        :eq -> true
        _ -> false
      end
    end)
  end

  defp fetch_weather_forecast(h3_index) do
    Repo.one(from wf in WeatherForecast, where: wf.h3_index == ^h3_index)
  end

  defp fetch_new_forecast(h3_index) do
    Client.query_grid_info(h3_index)
    |> insert_new_forecast(h3_index)
  end

  defp update_forecast({%{"expires" => datetime}, new_forecast, _grid_info}, existing_forecast) do
    {:ok, datetime} =
      Timex.parse(datetime, "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s} {Zname}")

    existing_forecast
    |> WeatherForecast.changeset(%{forecast: new_forecast, expires: datetime})
    |> Repo.update()
  end

  defp update_forecast({:error, _}, _), do: :noop

  defp insert_new_forecast(
         {%{"expires" => datetime}, forecast, %{"grid_id" => id, "grid_x" => x, "grid_y" => y}},
         h3_index
       ) do
    {lat, lng} = :h3.to_geo(h3_index)
    coords = %Geo.Point{coordinates: {lng, lat}, srid: 4326}

    {:ok, datetime} =
      Timex.parse(datetime, "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s} {Zname}")

    %WeatherForecast{}
    |> WeatherForecast.changeset(%{
      forecast: forecast,
      nws_grid_id: id,
      nws_grid_x: x,
      nws_grid_y: y,
      h3_index: h3_index,
      coords: coords,
      expires: datetime
    })
    |> Repo.insert()
  end

  defp insert_new_forecast({:error, _}, _), do: :noop
end
