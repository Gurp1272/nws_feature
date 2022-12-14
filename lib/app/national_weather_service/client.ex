defmodule App.NationalWeatherService.Client do
  @moduledoc """
  Handles queries to the NWS weather api
  """
  require Logger
  alias Frontline.NationalWeatherService.Parser

  @service "https://api.weather.gov"

  @doc """
  Forecast data is queried using NWS office id and grid coordinates. If those aren't initially available, you query for that grid information using a lat lng.
  """
  def query_grid_info(h3_index) do
    {lat, lng} =
      :h3.to_geo(h3_index)
      |> Tuple.to_list()
      |> Enum.map(&Float.round(&1, 4))
      |> List.to_tuple()

    :get
    |> Finch.build(
      grid_info_url(lat, lng),
      [{"Accept", "application/json"}, {"Content-Type", "application/json"}]
    )
    |> Finch.request(HTTPClient)
    |> handle_result()
    |> match_and_query()
  end

  def query_grid_forecast(id, x, y) do
    :get
    |> Finch.build(
      grid_forecast_url(id, x, y),
      [
        {"Accept", "application/geo+json"},
        {"User-Agent", "Frontline Wildfire <software@frontlinewildfire.com>"}
      ]
    )
    |> Finch.request(HTTPClient)
    |> handle_result()
    |> process_result(%{"grid_id" => id, "grid_x" => x, "grid_y" => y})
  end

  defp handle_result({:ok, %Finch.Response{body: body, headers: headers, status: status}})
       when status >= 200 and status < 300 do
    headers =
      headers
      |> Enum.into(%{})

    body =
      body
      |> Jason.decode!()

    {headers, body}
  end

  defp handle_result({:ok, %Finch.Response{body: body, status: status}}) do
    Logger.warn("api.weather.gov - Status: #{status} Body: #{body}")
    {:error, status}
  end

  defp handle_result({:error, er}) do
    Logger.warn("Error: #{inspect(er)}")
    {:error, Exception.message(er)}
  end

  defp process_result({:error, _} = error, _grid), do: error
  defp process_result({headers, body}, grid), do: {headers, Parser.run(body), grid}

  defp match_and_query({:error, _} = error), do: error

  defp match_and_query(
         {_headers,
          %{
            "properties" => %{"gridId" => grid_id, "gridX" => grid_x, "gridY" => grid_y}
          }}
       ) do
    query_grid_forecast(grid_id, grid_x, grid_y)
  end

  defp grid_info_url(lat, lng) do
    "#{@service}/points/#{lat},#{lng}"
  end

  defp grid_forecast_url(id, x, y) do
    "#{@service}/gridpoints/#{id}/#{x},#{y}"
  end
end
