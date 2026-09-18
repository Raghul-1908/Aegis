import 'services/prefs_service.dart';

class AppStrings {
  static const _labels = <AppLanguage, Map<String, String>>{
    AppLanguage.english: {
      'home': 'Home', 'notifications': 'Notifications', 'profile': 'Profile',
      'appearance': 'Appearance', 'theme': 'Theme', 'tileSize': 'Tile Size',
      'homeSections': 'Home Sections', 'accent': 'Accent Colour', 'language': 'Language',
      'riskScore': 'Risk Score', 'recent': 'Recent Risky Messages', 'summary': 'Summary',
      'goodMorning': 'Good morning', 'goodAfternoon': 'Good afternoon', 'goodEvening': 'Good evening',
    },
    AppLanguage.tamil: {
      'home': 'முகப்பு', 'notifications': 'அறிவிப்புகள்', 'profile': 'சுயவிவரம்',
      'appearance': 'தோற்றம்', 'theme': 'தீம்', 'tileSize': 'டைல் அளவு', 'homeSections': 'முகப்பு பகுதிகள்',
      'accent': 'முக்கிய நிறம்', 'language': 'மொழி', 'riskScore': 'ஆபத்து மதிப்பெண்', 'recent': 'சமீபத்திய ஆபத்தான செய்திகள்', 'summary': 'சுருக்கம்',
      'goodMorning': 'காலை வணக்கம்', 'goodAfternoon': 'மதிய வணக்கம்', 'goodEvening': 'மாலை வணக்கம்',
    },
    AppLanguage.hindi: {'home': 'होम', 'notifications': 'सूचनाएं', 'profile': 'प्रोफ़ाइल', 'appearance': 'दिखावट', 'theme': 'थीम', 'tileSize': 'टाइल आकार', 'homeSections': 'होम अनुभाग', 'accent': 'एक्सेंट रंग', 'language': 'भाषा', 'riskScore': 'जोखिम स्कोर', 'recent': 'हाल के जोखिम वाले संदेश', 'summary': 'सारांश', 'goodMorning': 'सुप्रभात', 'goodAfternoon': 'नमस्कार', 'goodEvening': 'शुभ संध्या'},
    AppLanguage.telugu: {'home': 'హోమ్', 'notifications': 'నోటిఫికేషన్లు', 'profile': 'ప్రొఫైల్', 'appearance': 'రూపం', 'theme': 'థీమ్', 'tileSize': 'టైల్ పరిమాణం', 'homeSections': 'హోమ్ విభాగాలు', 'accent': 'యాక్సెంట్ రంగు', 'language': 'భాష', 'riskScore': 'రిస్క్ స్కోర్', 'recent': 'ఇటీవలి ప్రమాదకర సందేశాలు', 'summary': 'సారాంశం', 'goodMorning': 'శుభోదయం', 'goodAfternoon': 'శుభ మధ్యాహ్నం', 'goodEvening': 'శుభ సాయంత్రం'},
    AppLanguage.malayalam: {'home': 'ഹോം', 'notifications': 'അറിയിപ്പുകൾ', 'profile': 'പ്രൊഫൈൽ', 'appearance': 'രൂപം', 'theme': 'തീം', 'tileSize': 'ടൈൽ വലുപ്പം', 'homeSections': 'ഹോം വിഭാഗങ്ങൾ', 'accent': 'ആക്സന്റ് നിറം', 'language': 'ഭാഷ', 'riskScore': 'റിസ്ക് സ്കോർ', 'recent': 'സമീപകാല അപകടകരമായ സന്ദേശങ്ങൾ', 'summary': 'സംഗ്രഹം', 'goodMorning': 'സുപ്രഭാതം', 'goodAfternoon': 'ശുഭ ഉച്ച', 'goodEvening': 'ശുഭ സായാഹ്നം'},
    AppLanguage.kannada: {'home': 'ಹೋಮ್', 'notifications': 'ಅಧಿಸೂಚನೆಗಳು', 'profile': 'ಪ್ರೊಫೈಲ್', 'appearance': 'ರೂಪ', 'theme': 'ಥೀಮ್', 'tileSize': 'ಟೈಲ್ ಗಾತ್ರ', 'homeSections': 'ಹೋಮ್ ವಿಭಾಗಗಳು', 'accent': 'ಆಕ್ಸೆಂಟ್ ಬಣ್ಣ', 'language': 'ಭಾಷೆ', 'riskScore': 'ಅಪಾಯ ಸ್ಕೋರ್', 'recent': 'ಇತ್ತೀಚಿನ ಅಪಾಯಕಾರಿ ಸಂದೇಶಗಳು', 'summary': 'ಸಾರಾಂಶ', 'goodMorning': 'ಶುಭೋದಯ', 'goodAfternoon': 'ಶುಭ ಮಧ್ಯಾಹ್ನ', 'goodEvening': 'ಶುಭ ಸಂಜೆ'},
  };

  static String get(String key) => _labels[PrefsService.language]?[key] ?? _labels[AppLanguage.english]![key] ?? key;
}
