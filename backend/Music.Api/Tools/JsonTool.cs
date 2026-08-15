using System.Text.Json;


namespace Music.Api.Tools;

public class JsonTool
{
	public static string Serialize(object obj)
	{
		return JsonSerializer.Serialize(obj);
	}

	public static T Deserialize<T>(string json)
	{
		if(string.IsNullOrWhiteSpace(json)) 
			throw new ArgumentNullException(nameof(json));
		return JsonSerializer.Deserialize<T>(json);
	}
}