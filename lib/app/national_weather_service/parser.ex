defmodule App.NationalWeatherService.Parser do
  @moduledoc """
  Parses the NWS forecast feed into hourly chunks, assigning the closest value to the given chunk. Only computes 24 hours
  """
  @ignored_fields ~w[@id @type updateTime validTimes elevation forecastOffice gridX gridY gridId]

  @hours_to_parse 24

  defmodule Duration do
    defstruct ~w[years months weeks days hours minutes seconds]a
  end

  def run(%{"properties" => props}) do
    props = Map.drop(props, @ignored_fields)
    datetimes = generate_datetimes(props)
    generate_forecasts(datetimes, props)
  end

  defp generate_forecasts(datetimes, props) do
    Enum.reduce(datetimes, %{}, fn dt, acc ->
      Map.put(acc, dt, get_values(dt, props))
    end)
  end

  defp get_values(dt, props) do
    Enum.reduce(props, %{}, fn {k, %{"values" => values}}, acc ->
      v =
        case get_closest_value(dt, values) do
          %{"value" => v} -> v
          nil -> nil
        end

      Map.put(acc, k, v)
    end)
  end

  defp get_closest_value(dt, values) do
    Enum.find(values, fn %{"validTime" => vt} ->
      {start, finish} = parse_range(vt)

      with :gt <- DateTime.compare(dt, start),
           :lt <- DateTime.compare(dt, finish) do
        true
      else
        :eq -> true
        _ -> false
      end
    end)
  end

  defp generate_datetimes(fields) do
    fields
    |> Enum.flat_map(fn {_k, %{"values" => values}} ->
      Enum.map(values, fn %{"validTime" => dt} -> dt end)
    end)
    |> Enum.flat_map(&generate_duration_timestamps/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.slice(0..@hours_to_parse)
  end

  defp parse_range(datetime) do
    [datetime, duration] = String.split(datetime, "/")

    dur = parse_duration(duration, "", false, %Duration{})

    {:ok, datetime, _} = DateTime.from_iso8601(datetime)
    {datetime, add_duration(datetime, dur)}
  end

  defp generate_duration_timestamps(datetime) do
    range = parse_range(datetime)
    datetime_fill(range)
  end

  defp add_duration(dt, dur) do
    dt
    |> add_duration(:years, dur.years)
    |> add_duration(:months, dur.months)
    |> add_duration(:weeks, dur.weeks)
    |> add_duration(:days, dur.days)
    |> add_duration(:hours, dur.hours)
    |> add_duration(:minutes, dur.minutes)
    |> add_duration(:seconds, dur.seconds)
  end

  defp datetime_fill({start, finish}) do
    diff = DateTime.diff(start, finish, :second)

    hours = trunc(diff / 3600)

    Enum.reduce(0..hours, [start], fn _, [dt | _] = acc ->
      [DateTime.add(dt, 3600, :second) | acc]
    end)
  end

  defp add_duration(datetime, _, nil), do: datetime

  defp add_duration(datetime, :years, years),
    do: DateTime.add(datetime, years * (365 * 86_400), :second)

  defp add_duration(datetime, :months, months),
    do: DateTime.add(datetime, months * (30 * 86_400), :second)

  defp add_duration(datetime, :weeks, weeks),
    do: DateTime.add(datetime, weeks * (7 * 86_400), :second)

  defp add_duration(datetime, :days, days), do: DateTime.add(datetime, days * 86_400, :second)
  defp add_duration(datetime, :hours, hours), do: DateTime.add(datetime, hours * 3600, :second)

  defp add_duration(datetime, :minutes, minutes),
    do: DateTime.add(datetime, minutes * 60, :second)

  defp add_duration(datetime, :seconds, seconds), do: DateTime.add(datetime, seconds, :second)

  defp parse_duration("", _, _, res), do: res

  defp parse_duration(<<"P", rest::binary>>, _string, _, res),
    do: parse_duration(rest, "", false, res)

  defp parse_duration(<<"Y", rest::binary>>, string, _, res),
    do: parse_duration(rest, "", false, %Duration{res | years: String.to_integer(string)})

  defp parse_duration(<<"M", rest::binary>>, string, false, res),
    do: parse_duration(rest, "", false, %Duration{res | months: String.to_integer(string)})

  defp parse_duration(<<"W", rest::binary>>, string, _, res),
    do: parse_duration(rest, "", false, %Duration{res | weeks: String.to_integer(string)})

  defp parse_duration(<<"D", rest::binary>>, string, _, res),
    do: parse_duration(rest, "", false, %Duration{res | days: String.to_integer(string)})

  defp parse_duration(<<"T", rest::binary>>, _string, _, res),
    do: parse_duration(rest, "", true, res)

  defp parse_duration(<<"H", rest::binary>>, string, _, res),
    do: parse_duration(rest, "", true, %Duration{res | hours: String.to_integer(string)})

  defp parse_duration(<<"M", rest::binary>>, string, _, res),
    do: parse_duration(rest, "", true, %Duration{res | minutes: String.to_integer(string)})

  defp parse_duration(<<"S", rest::binary>>, string, _, res),
    do: parse_duration(rest, "", true, %Duration{res | seconds: String.to_integer(string)})

  defp parse_duration(<<s::binary-size(1), rest::binary>>, string, time?, res),
    do: parse_duration(rest, string <> s, time?, res)
end
