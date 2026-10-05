import 'dart:js_interop';

@JS('downloadBase64File')
external void downloadBase64File(String base64Data, String fileName);

@JS('playRingAudio')
external void playRingAudio();

@JS('stopRingAudio')
external void stopRingAudio();

@JS('playHangupAudio')
external void playHangupAudio();
