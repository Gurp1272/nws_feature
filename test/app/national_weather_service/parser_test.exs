defmodule App.NationalWeatherService.ParserTest do
  use App.DataCase
  alias App.NationalWeatherService.Parser

  test "run" do
    path = Path.join([File.cwd!(), "test", "support", "nws.json"])
    data = File.read!(path)
    data = Jason.decode!(data)
    assert %{~U[2022-09-20 19:00:00Z] => %{"temperature" => 22.77777777777778}} = Parser.run(data)
  end
end
