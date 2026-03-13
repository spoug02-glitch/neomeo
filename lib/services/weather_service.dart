// lib/services/weather_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

  static Future<Map<String, dynamic>?> fetchWeather(double lat, double lon, String apiKey) async {
    if (apiKey.isEmpty) return null;
    try {
      final url = Uri.parse('$_baseUrl/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Weather fetch error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> fetchAirPollution(double lat, double lon, String apiKey) async {
    if (apiKey.isEmpty) return null;
    try {
      final url = Uri.parse('$_baseUrl/air_pollution?lat=$lat&lon=$lon&appid=$apiKey');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Air pollution fetch error: $e');
    }
    return null;
  }

  static Future<List<dynamic>?> fetchForecast(double lat, double lon, String apiKey) async {
    if (apiKey.isEmpty) return null;
    try {
      final url = Uri.parse('$_baseUrl/forecast?lat=$lat&lon=$lon&appid=$apiKey&units=metric');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['list'] as List?;
      }
    } catch (e) {
      // ignore: avoid_print
      print('Forecast fetch error: $e');
    }
    return null;
  }

  static String calculateRecommendedClothes(double temp) {
    if (temp >= 28) return '민소매, 반바지, 린넨 옷';
    if (temp >= 23) return '반팔, 얇은 셔츠, 면바지';
    if (temp >= 20) return '블라우스, 긴팔 티, 면바지, 슬랙스';
    if (temp >= 17) return '얇은 가디건, 니트, 맨투맨, 청바지';
    if (temp >= 12) return '자켓, 가디건, 야상, 스타킹, 청바지';
    if (temp >= 9) return '트렌치 코트, 간절기 야상, 스타킹, 기모바지';
    if (temp >= 5) return '울 코트, 히트텍, 가죽 옷, 기모';
    return '패딩, 두꺼운 코트, 목도리, 기모제품';
  }

  static bool shouldBringUmbrella(Map<String, dynamic>? weatherData) {
    if (weatherData == null) return false;
    final weather = weatherData['weather'] as List?;
    if (weather == null || weather.isEmpty) return false;
    
    final main = weather[0]['main']?.toString().toLowerCase() ?? '';
    // Rain, Snow, Drizzle, Thunderstorm usually require umbrellas
    return main.contains('rain') || main.contains('snow') || main.contains('drizzle') || main.contains('thunderstorm');
  }

  static bool shouldWearMask(Map<String, dynamic>? airData) {
    if (airData == null) return false;
    final list = airData['list'] as List?;
    if (list == null || list.isEmpty) return false;

    final main = list[0]['main'];
    if (main == null) return false;

    final aqi = main['aqi'] as int? ?? 1;
    // AQI levels: 1 = Good, 2 = Fair, 3 = Moderate, 4 = Poor, 5 = Very Poor
    // Suggest mask for Poor (4) and Very Poor (5)
    return aqi >= 4;
  }

  /// 단순 옷차림 레이블 (평균 온도 기반, 1~2단어)
  static String getSimpleClothing(double temp) {
    if (temp >= 28) return '민소매·반바지';
    if (temp >= 23) return '반팔';
    if (temp >= 20) return '긴팔';
    if (temp >= 17) return '니트·맨투맨';
    if (temp >= 12) return '자켓·청바지';
    if (temp >= 9)  return '트렌치코트';
    if (temp >= 5)  return '울코트';
    return '패딩';
  }

  /// OWM AQI (1~5) → 한국어 레이블
  static String getAqiLabel(int aqi) {
    switch (aqi) {
      case 1: return '좋음';
      case 2: return '보통';
      case 3: return '보통';
      case 4: return '나쁨';
      case 5: return '매우나쁨';
      default: return '-';
    }
  }

  /// forecast 다음 4구간(12h) 중 최대 강수확률 0~100
  static int getMaxPrecipProb(List<dynamic> forecast) {
    if (forecast.isEmpty) return 0;
    final maxPop = forecast
        .take(4)
        .map((e) => (e['pop'] as num? ?? 0.0).toDouble())
        .reduce((a, b) => a > b ? a : b);
    return (maxPop * 100).round();
  }

  /// forecast 다음 4구간 중 눈 예보 여부
  static bool isSnowExpected(List<dynamic> forecast) {
    return forecast.take(4).any((e) {
      final w = e['weather'] as List?;
      if (w == null || w.isEmpty) return false;
      return (w[0]['main']?.toString().toLowerCase() ?? '').contains('snow');
    });
  }

  /// air_pollution 응답에서 AQI 정수 (0 = 데이터 없음)
  static int getAqiValue(Map<String, dynamic>? airData) {
    if (airData == null) return 0;
    final list = airData['list'] as List?;
    if (list == null || list.isEmpty) return 0;
    final main = list[0]['main'];
    if (main == null) return 0;
    return (main['aqi'] as int?) ?? 0;
  }
}
