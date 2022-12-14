defmodule App.NationalWeatherService.ApiTest do
  use App.DataCase

  alias App.NationalWeatherService.{API, Conditions, Parser}
  alias App.NationalWeatherService.Schema.WeatherForecast
  alias App.Repo
  alias App.Schema.Property

  @h3_index 617_713_504_384_450_559
  @h3_index2 599_686_014_516_068_351

  @property %Property{
    h3_index: @h3_index
  }

  @property2 %Property{
    h3_index: @h3_index2
  }
  setup do
    path = Path.join([File.cwd!(), "test", "support", "nws.json"])
    data = File.read!(path)
    data = Jason.decode!(data)
    forecast = Parser.run(data)

    {:ok, forecast} =
      create_data(
        forecast,
        "1",
        1,
        1,
        @h3_index2,
        %Geo.Point{coordinates: {90, -30}, srid: 4326},
        DateTime.utc_now()
      )

    %{forecast: forecast}
  end

  test "current_forecast" do
    assert %Conditions{id: @h3_index2, temperature: 25} =
             API.current_forecast(@property2, ~U[2022-09-21 17:00:00Z])
  end

  @tag :integration
  test "API" do
    start_time =
      DateTime.utc_now()
      |> DateTime.add(-28_800)

    end_time =
      DateTime.utc_now()
      |> DateTime.add(28_800)

    assert {:ok, weather_forecast} = API.new_weather_forecast(@h3_index)
    assert {:ok, _} = API.update_weather_forecast(weather_forecast)
    assert {:ok, [%{} | _tail]} = API.forecast(@property, start_time, end_time)
  end

  defp create_data(forecast, id, x, y, h3_index, coords, datetime) do
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
end
