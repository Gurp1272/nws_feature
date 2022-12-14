defmodule App.Repo.Migrations.CreateWeatherTable do
  use Ecto.Migration

  def up do
    create table("weather_forecasts", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :nws_grid_id, :string
      add :nws_grid_x, :integer
      add :nws_grid_y, :integer
      add :h3_index, :bigint
      add :forecast, :map, default: %{}
      add :expires, :utc_datetime

      timestamps()
    end

    create unique_index("weather_forecasts", [:h3_index])

    execute("SELECT AddGeometryColumn ('weather_forecasts', 'coords', 4326, 'POINT', 2);")
    create index("weather_forecasts", [:coords], using: "GIST")

    create index("weather_forecasts", [:expires])
  end

  def down do
    drop table("weather_forecasts")
  end
end
