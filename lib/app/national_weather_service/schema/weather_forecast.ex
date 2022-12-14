defmodule App.NationalWeatherService.Schema.WeatherForecast do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @timestamps_opts [type: :utc_datetime_usec]
  schema "weather_forecasts" do
    field :nws_grid_id, :string
    field :nws_grid_x, :integer
    field :nws_grid_y, :integer
    field :h3_index, :integer
    field :coords, Geo.PostGIS.Geometry
    field :forecast, :map, default: %{}
    field :expires, :utc_datetime

    timestamps()
  end

  def changeset(forecast, attrs) do
    forecast
    |> cast(
      attrs,
      ~w[nws_grid_id nws_grid_x nws_grid_y h3_index coords forecast expires]a
    )
    |> validate_required(~w[nws_grid_id nws_grid_x nws_grid_y h3_index coords forecast expires]a)
    |> unique_constraint(:h3_index)
    |> validate_number(:h3_index, greater_than_or_equal_to: 0)
  end
end
