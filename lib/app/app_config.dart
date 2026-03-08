// lib/app/app_config.dart
//
// 앱 빌드 시 개발자가 직접 제공하는 설정값.
// 사용자에게 노출되지 않는다.

class AppConfig {
  AppConfig._();

  /// OpenWeatherMap API Key (https://openweathermap.org/api)
  /// 날씨/미세먼지 기능이 자동으로 활성화된다.
  static const String weatherApiKey = 'YOUR_OWM_API_KEY_HERE';
}
